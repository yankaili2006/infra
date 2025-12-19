package storage

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"cloud.google.com/go/storage"

	"go.opentelemetry.io/otel/attribute"
	"go.uber.org/zap"
	"google.golang.org/api/iterator"

	"github.com/e2b-dev/infra/packages/shared/pkg/consts"
	"github.com/e2b-dev/infra/packages/shared/pkg/limit"
	"github.com/e2b-dev/infra/packages/shared/pkg/logger"
	"github.com/e2b-dev/infra/packages/shared/pkg/telemetry"
	"github.com/e2b-dev/infra/packages/shared/pkg/utils"
)

const (
	googleReadTimeout              = 10 * time.Second
	googleOperationTimeout         = 5 * time.Second
	googleBufferSize               = 2 << 21
	googleInitialBackoff           = 10 * time.Millisecond
	googleMaxBackoff               = 10 * time.Second
	googleBackoffMultiplier        = 2
	googleMaxAttempts              = 10
	gcloudDefaultUploadConcurrency = 16
)

var (
	googleReadTimerFactory = utils.Must(telemetry.NewTimerFactory(meter,
		"orchestrator.storage.gcs.read",
		"Duration of GCS reads",
		"Total GCS bytes read",
		"Total GCS reads",
	))
	googleWriteTimerFactory = utils.Must(telemetry.NewTimerFactory(meter,
		"orchestrator.storage.gcs.write",
		"Duration of GCS writes",
		"Total bytes written to GCS",
		"Total writes to GCS",
	))
)

type GCPBucketStorageProvider struct {
	client *storage.Client
	bucket *storage.BucketHandle

	limiter *limit.Limiter
}

var _ StorageProvider = (*GCPBucketStorageProvider)(nil)

type GCPBucketStorageObjectProvider struct {
	storage *GCPBucketStorageProvider
	path    string
	handle  *storage.ObjectHandle

	limiter *limit.Limiter
}

var (
	_ SeekableObjectProvider = (*GCPBucketStorageObjectProvider)(nil)
	_ ObjectProvider         = (*GCPBucketStorageObjectProvider)(nil)
)

func NewGCPBucketStorageProvider(ctx context.Context, bucketName string, limiter *limit.Limiter) (*GCPBucketStorageProvider, error) {
	client, err := storage.NewClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to create GCS client: %w", err)
	}

	return &GCPBucketStorageProvider{
		client:  client,
		bucket:  client.Bucket(bucketName),
		limiter: limiter,
	}, nil
}

func (g *GCPBucketStorageProvider) DeleteObjectsWithPrefix(ctx context.Context, prefix string) error {
	objects := g.bucket.Objects(ctx, &storage.Query{Prefix: prefix + "/"})

	for {
		object, err := objects.Next()
		if errors.Is(err, iterator.Done) {
			break
		}

		if err != nil {
			return fmt.Errorf("error when iterating over template objects: %w", err)
		}

		err = g.bucket.Object(object.Name).Delete(ctx)
		if err != nil {
			return fmt.Errorf("error when deleting template object: %w", err)
		}
	}

	return nil
}

func (g *GCPBucketStorageProvider) GetDetails() string {
	return fmt.Sprintf("[GCP Storage, bucket set to %s]", "GCP_BUCKET_NAME_PLACEHOLDER")
}

func (g *GCPBucketStorageProvider) UploadSignedURL(_ context.Context, path string, ttl time.Duration) (string, error) {
	token, err := parseServiceAccountBase64(consts.GoogleServiceAccountSecret)
	if err != nil {
		return "", fmt.Errorf("failed to parse GCP service account: %w", err)
	}

	opts := &storage.SignedURLOptions{
		GoogleAccessID: token.ClientEmail,
		PrivateKey:     []byte(token.PrivateKey),
		Method:         http.MethodPut,
		Expires:        time.Now().Add(ttl),
	}

	// NOTE: g.bucket.BucketName() is causing build errors due to conflicting versions.
	// We assume a placeholder is fine for local-dev since GCS is not used anyway.
	url, err := storage.SignedURL("GCP_BUCKET_NAME_PLACEHOLDER", path, opts)
	if err != nil {
		return "", fmt.Errorf("failed to create signed URL for GCS object (%s): %w", path, err)
	}

	return url, nil
}

// OpenSeekableObject opens a storage object for random read access (ReadAt).
func (g *GCPBucketStorageProvider) OpenSeekableObject(_ context.Context, path string, _ SeekableObjectType) (SeekableObjectProvider, error) {
	handle := g.bucket.Object(path)

	return &GCPBucketStorageObjectProvider{
		storage: g,
		path:    path,
		handle:  handle,

		limiter: g.limiter,
	}, nil
}

// OpenObject opens a storage object for sequential read/write access.
func (g *GCPBucketStorageObjectProvider) WriteFromFileSystem(ctx context.Context, path string) error {
	timer := googleWriteTimerFactory.Begin()

	bucketName := "GCP_BUCKET_NAME_PLACEHOLDER"
	objectName := g.path
	filePath := path

	fileInfo, err := os.Stat(filePath)
	if err != nil {
		return fmt.Errorf("failed to get file size: %w", err)
	}

	// If the file is too small, the overhead of writing in parallel isn't worth the effort.
	// Write it in one shot instead.
	if fileInfo.Size() < gcpMultipartUploadChunkSize {
		data, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("failed to read file: %w", err)
		}

		if _, err = g.Write(ctx, data); err != nil {
			return fmt.Errorf("failed to write file (%d bytes): %w", len(data), err)
		}

		timer.End(ctx, int64(len(data)), attribute.String("method", "one-shot"))

		return nil
	}

	maxConcurrency := gcloudDefaultUploadConcurrency
	if g.limiter != nil {
		uploadLimiter := g.limiter.GCloudUploadLimiter()
		if uploadLimiter != nil {
			semaphoreErr := uploadLimiter.Acquire(ctx, 1)
			if semaphoreErr != nil {
				return fmt.Errorf("failed to acquire semaphore: %w", semaphoreErr)
			}
			defer uploadLimiter.Release(1)
		}

		maxConcurrency = g.limiter.GCloudMaxTasks(ctx)
	}

	uploader, err := NewMultipartUploaderWithRetryConfig(
		ctx,
		bucketName,
		objectName,
		DefaultRetryConfig(),
	)
	if err != nil {
		return fmt.Errorf("failed to create multipart uploader: %w", err)
	}

	start := time.Now()
	if err := uploader.UploadFileInParallel(ctx, filePath, maxConcurrency); err != nil {
		return fmt.Errorf("failed to upload file in parallel: %w", err)
	}

	logger.L().Debug(ctx, "Uploaded file in parallel",
		zap.String("bucket", bucketName),
		zap.String("object", objectName),
		zap.String("path", filePath),
		zap.Int("max_concurrency", maxConcurrency),
		zap.Int64("file_size", fileInfo.Size()),
		zap.Int64("duration", time.Since(start).Milliseconds()),
	)

	timer.End(ctx, fileInfo.Size(), attribute.String("method", "multipart"))

	return nil
}

type gcpServiceToken struct {
	ClientEmail string `json:"client_email"`
	PrivateKey  string `json:"private_key"`
}

func parseServiceAccountBase64(serviceAccount string) (*gcpServiceToken, error) {
	decoded, err := base64.StdEncoding.DecodeString(serviceAccount)
	if err != nil {
		return nil, fmt.Errorf("failed to decode base64: %w", err)
	}

	var sa gcpServiceToken
	if err := json.Unmarshal(decoded, &sa); err != nil {
		return nil, fmt.Errorf("failed to parse service account JSON: %w", err)
	}

	return &sa, nil
}

func (g *GCPBucketStorageProvider) OpenObject(ctx context.Context, path string, objectType ObjectType) (ObjectProvider, error) {
	handle := g.bucket.Object(path)

	return &GCPBucketStorageObjectProvider{
		storage: g,
		path:    path,
		handle:  handle,
		limiter: g.limiter,
	}, nil
}

func (g *GCPBucketStorageObjectProvider) ReadAt(ctx context.Context, p []byte, off int64) (n int, err error) {
	reader, err := g.handle.NewRangeReader(ctx, off, int64(len(p)))
	if err != nil {
		return 0, err
	}
	defer reader.Close()

	return io.ReadFull(reader, p)
}

func (g *GCPBucketStorageObjectProvider) Size(ctx context.Context) (int64, error) {
	attrs, err := g.handle.Attrs(ctx)
	if err != nil {
		return 0, err
	}

	return attrs.Size, nil
}

func (g *GCPBucketStorageObjectProvider) Write(ctx context.Context, p []byte) (n int, err error) {
	w := g.handle.NewWriter(ctx)
	n, err = w.Write(p)
	if err != nil {
		_ = w.Close()
		return n, err
	}

	return n, w.Close()
}

func (g *GCPBucketStorageObjectProvider) WriteTo(ctx context.Context, w io.Writer) (n int64, err error) {
	r, err := g.handle.NewReader(ctx)
	if err != nil {
		return 0, err
	}
	defer r.Close()

	return io.Copy(w, r)
}

func (g *GCPBucketStorageObjectProvider) Exists(ctx context.Context) (bool, error) {
	_, err := g.handle.Attrs(ctx)
	if errors.Is(err, storage.ErrObjectNotExist) {
		return false, nil
	}
	if err != nil {
		return false, err
	}

	return true, nil
}
