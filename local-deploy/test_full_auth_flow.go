package main

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"fmt"
	"strings"

	_ "github.com/lib/pq"
)

func main() {
	// Step 1: Simulate API receiving request
	apiKey := "e2b_53ae1fed82754c17ad8077fbc8bcdd90"
	fmt.Printf("=== Step 1: Received API Key ===\n")
	fmt.Printf("API Key: %s\n\n", apiKey)

	// Step 2: Verify and hash the key (simulating keys.VerifyKey)
	prefix := "e2b_"
	if !strings.HasPrefix(apiKey, prefix) {
		fmt.Println("ERROR: Invalid prefix")
		return
	}

	keyValue := apiKey[len(prefix):]
	fmt.Printf("=== Step 2: Strip Prefix ===\n")
	fmt.Printf("Key value: %s\n\n", keyValue)

	// Decode hex
	keyBytes, err := hex.DecodeString(keyValue)
	if err != nil {
		fmt.Printf("ERROR: Failed to decode hex: %v\n", err)
		return
	}

	fmt.Printf("=== Step 3: Decode Hex ===\n")
	fmt.Printf("Decoded bytes: %v\n", keyBytes)
	fmt.Printf("Bytes length: %d\n\n", len(keyBytes))

	// SHA256 hash
	hasher := sha256.New()
	hasher.Write(keyBytes)
	hashBytes := hasher.Sum(nil)
	hashedApiKey := hex.EncodeToString(hashBytes)

	fmt.Printf("=== Step 4: SHA256 Hash ===\n")
	fmt.Printf("Hashed API Key: %s\n", hashedApiKey)
	fmt.Printf("Hash length: %d\n\n", len(hashedApiKey))

	// Step 3: Connect to database
	connStr := "postgres://postgres:postgres@127.0.0.1:5432/postgres?sslmode=disable"
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		fmt.Printf("ERROR: Failed to connect to database: %v\n", err)
		return
	}
	defer db.Close()

	err = db.Ping()
	if err != nil {
		fmt.Printf("ERROR: Failed to ping database: %v\n", err)
		return
	}

	fmt.Printf("=== Step 5: Database Connection ===\n")
	fmt.Printf("✓ Connected to database\n\n")

	// Step 4: Execute the EXACT query from the API code
	fmt.Printf("=== Step 6: Execute API Query ===\n")
	fmt.Printf("Using hash: %s\n\n", hashedApiKey)

	query := `
		UPDATE "public"."team_api_keys" tak
		SET last_used = now()
		FROM "public"."teams" t
		JOIN "public"."team_limits" tl on tl.id = t.id
		WHERE tak.team_id = t.id
		  AND tak.api_key_hash = $1
		RETURNING t.id, t.created_at, t.is_blocked, t.name, t.tier, t.email, t.is_banned, t.blocked_reason, t.cluster_id, tl.id, tl.max_length_hours, tl.concurrent_sandboxes, tl.concurrent_template_builds, tl.max_vcpu, tl.max_ram_mb, tl.disk_mb
	`

	ctx := context.Background()
	row := db.QueryRowContext(ctx, query, hashedApiKey)

	var (
		teamID, teamName, tier, email string
		createdAt                     interface{}
		isBlocked, isBanned           bool
		blockedReason                 sql.NullString
		clusterID                     sql.NullString
		limitID                       string
		maxLengthHours                int
		concurrentSandboxes           int
		concurrentTemplateBuilds      int
		maxVcpu                       int
		maxRamMb                      int
		diskMb                        int
	)

	err = row.Scan(
		&teamID, &createdAt, &isBlocked, &teamName, &tier, &email,
		&isBanned, &blockedReason, &clusterID,
		&limitID, &maxLengthHours, &concurrentSandboxes, &concurrentTemplateBuilds,
		&maxVcpu, &maxRamMb, &diskMb,
	)

	if err == sql.ErrNoRows {
		fmt.Printf("❌ ERROR: No rows returned!\n\n")

		// Debug: Check what's in the database
		fmt.Printf("=== Debug: Check Database ===\n")
		var dbHash string
		err2 := db.QueryRow("SELECT api_key_hash FROM team_api_keys WHERE team_id = 'a90209cf-2ab1-4dd5-93f6-cabc5c2d7eae'").Scan(&dbHash)
		if err2 != nil {
			fmt.Printf("ERROR: Failed to query database hash: %v\n", err2)
			return
		}

		fmt.Printf("Hash in DB:      %s\n", dbHash)
		fmt.Printf("Hash we used:    %s\n", hashedApiKey)
		fmt.Printf("Hashes match:    %v\n", dbHash == hashedApiKey)
		fmt.Printf("DB hash length:  %d\n", len(dbHash))
		fmt.Printf("Our hash length: %d\n\n", len(hashedApiKey))

		// Character-by-character comparison
		if dbHash != hashedApiKey {
			fmt.Printf("=== Character Comparison ===\n")
			minLen := len(dbHash)
			if len(hashedApiKey) < minLen {
				minLen = len(hashedApiKey)
			}

			for i := 0; i < minLen; i++ {
				if dbHash[i] != hashedApiKey[i] {
					fmt.Printf("First difference at position %d:\n", i)
					fmt.Printf("  DB:  '%c' (0x%02x)\n", dbHash[i], dbHash[i])
					fmt.Printf("  Our: '%c' (0x%02x)\n", hashedApiKey[i], hashedApiKey[i])
					break
				}
			}
		}

		return
	} else if err != nil {
		fmt.Printf("❌ ERROR: Query failed: %v\n", err)
		return
	}

	fmt.Printf("✅ SUCCESS! Team found:\n")
	fmt.Printf("  Team ID: %s\n", teamID)
	fmt.Printf("  Name: %s\n", teamName)
	fmt.Printf("  Email: %s\n", email)
	fmt.Printf("  Tier: %s\n", tier)
	fmt.Printf("  Is Blocked: %v\n", isBlocked)
	fmt.Printf("  Is Banned: %v\n", isBanned)
	fmt.Printf("  Concurrent Sandboxes: %d\n", concurrentSandboxes)
}
