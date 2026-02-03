package db

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/e2b-dev/infra/packages/api/internal/db/types"
	sqlcdb "github.com/e2b-dev/infra/packages/db/client"
	"github.com/e2b-dev/infra/packages/db/queries"
)

type TeamForbiddenError struct {
	message string
}

func (e *TeamForbiddenError) Error() string {
	return e.message
}

type TeamBlockedError struct {
	message string
}

func (e *TeamBlockedError) Error() string {
	return e.message
}

func validateTeamUsage(team queries.Team) error {
	if team.IsBanned {
		return &TeamForbiddenError{message: "team is banned"}
	}

	if team.IsBlocked {
		return &TeamBlockedError{message: "team is blocked"}
	}

	return nil
}

func GetTeamAuth(ctx context.Context, db *sqlcdb.Client, apiKey string) (*types.Team, error) {
	// DEBUG: Write to debug file
	os.WriteFile("/tmp/debug_api_key.txt", []byte(fmt.Sprintf("Hash: %s\nTime: %s\n", apiKey, time.Now())), 0644)

	result, err := db.GetTeamWithTierByAPIKeyWithUpdateLastUsed(ctx, apiKey)
	if err != nil {
		errMsg := fmt.Errorf("failed to get team from API key: %w", err)
		os.WriteFile("/tmp/debug_api_error.txt", []byte(fmt.Sprintf("Error: %v\n", err)), 0644)
		return nil, errMsg
	}

	err = validateTeamUsage(result.Team)
	if err != nil {
		return nil, err
	}

	team := types.NewTeam(&result.Team, &result.TeamLimit)

	return team, nil
}
