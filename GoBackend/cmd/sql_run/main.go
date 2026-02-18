// Package main provides a utility to run SQL statements against the database.
package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/yourorg/combatden-api/internal/config"
	"github.com/yourorg/combatden-api/internal/database"
)

// SQL query to execute - modify this multiline string as needed
const sqlQuery = `
SELECT email FROM auth.users
`

func main() {
	ctx := context.Background()

	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	fmt.Printf("Connecting to database (ENV: %s)...\n", cfg.Env)
	fmt.Printf("Database Location: %s\n", cfg.DatabaseURL)

	// Connect to database
	db, err := database.New(ctx, cfg.DatabaseURL, cfg.Database)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()

	fmt.Println("Connected successfully!")
	fmt.Println("\nExecuting SQL query...")
	fmt.Println("----------------------------------------")

	// Execute the SQL query
	rows, err := db.Pool.Query(ctx, sqlQuery)
	if err != nil {
		log.Fatalf("Failed to execute query: %v", err)
	}
	defer rows.Close()

	// Process results if any
	fmt.Println("Query executed successfully!")

	// Print column names
	fieldDescriptions := rows.FieldDescriptions()
	if len(fieldDescriptions) > 0 {
		fmt.Println("\nResults:")
		for _, fd := range fieldDescriptions {
			fmt.Printf("%-20s", fd.Name)
		}
		fmt.Println()
		fmt.Println("----------------------------------------")
	}

	// Print rows
	rowCount := 0
	for rows.Next() {
		values, err := rows.Values()
		if err != nil {
			log.Fatalf("Failed to read row: %v", err)
		}

		for _, v := range values {
			fmt.Printf("%-20v", v)
		}
		fmt.Println()
		rowCount++
	}

	if err := rows.Err(); err != nil {
		log.Fatalf("Error during row iteration: %v", err)
	}

	if rowCount > 0 {
		fmt.Printf("\nTotal rows: %d\n", rowCount)
	}

	fmt.Println("----------------------------------------")
	fmt.Println("Done!")
	os.Exit(0)
}
