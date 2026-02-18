# Go-Gin API Coding Standards

## General Principles

**SOLID Principles**
- Single Responsibility: Each struct/package has one well-defined purpose
- Open/Closed: Open for extension, closed for modification
- Interface Segregation: Many specific interfaces over one general-purpose

**Other Core Principles**
- DRY (Don't Repeat Yourself): Single source of truth for each piece of logic
- KISS (Keep It Simple): Favor simplicity over complexity
- YAGNI (You Aren't Gonna Need It): Don't add features until needed
- Separation of Concerns: Separate different aspects into distinct sections

**Development Workflow**
- **ALWAYS read the Makefile before running commands manually**
  - The Makefile contains standardized project commands
  - Use `make help` to see available commands
  - Prefer `make run`, `make build`, `make test`, etc. over manual go commands
  - The Makefile ensures consistency (e.g., `make run` runs `sqlc generate` first)
  - Only run commands manually if they're not in the Makefile or for one-off tasks
- Example:
  - Good: `make run` (uses project standards)
  - Bad: `go run cmd/api/main.go` (bypasses sqlc generation and other setup)

## Go Standards

**Imports**
- **ALWAYS organize imports in three groups** with blank lines between:
  1. Standard library packages
  2. External packages (third-party)
  3. Internal packages (your project)
- Use `goimports` for automatic formatting and organization
- Group imports in parentheses
- Good:
  ```go
  import (
      "context"
      "fmt"
      "time"

      "github.com/gin-gonic/gin"
      "github.com/google/uuid"

      "github.com/yourorg/yourproject/internal/user"
      "github.com/yourorg/yourproject/internal/logger"
  )
  ```
- Bad: Imports not grouped, missing blank lines between groups

**Naming Conventions**
- **Packages**: lowercase, short, no underscores (`user`, `auth`, not `user_service`)
- **Exported identifiers**: PascalCase (`UserService`, `CreateUser`, `HTTPClient`)
- **Unexported identifiers**: camelCase (`userRepository`, `hashPassword`, `userID`)
- **Interfaces**: Noun or Agent noun (`Reader`, `Writer`, `UserRepository`, `EmailSender`)
- **Acronyms**: Consistent case within identifier
  - Good: `HTTPServer`, `userID`, `URLPath`, `IDToken`
  - Bad: `HttpServer`, `userId`, `UrlPath`, `IdToken`
- **Constants**: Mixed case or ALL_CAPS based on scope
  - Exported: `MaxRetries`, `DefaultTimeout`
  - Configuration: `MAX_UPLOAD_SIZE`, `API_TIMEOUT`

**Formatting**
- **MUST run `make check`** - non-negotiable, Go standard
- Max 120 characters per line (soft limit, Go doesn't enforce)
- Use tabs for indentation (Go standard)
- One blank line between function/method definitions
- Let `gofmt` handle the rest

**Code Complexity & Nesting**
- **Limit deep nesting** - avoid nesting more than 3 levels deep
- **Use early returns (guard clauses)** to reduce nesting
- Good:
  ```go
  func ProcessUser(user *User) error {
      if user == nil {
          return ErrUserNil
      }
      if !user.IsActive {
          return ErrUserInactive
      }
      // Happy path with minimal nesting
      return processActiveUser(user)
  }
  ```
- Bad: Deep nesting with `if/else` chains
- **Extract functions when nesting gets complex** - create helper functions
- Benefits: Easier to test, read, and maintain; follows Single Responsibility Principle

**Error Handling**
- **ALWAYS handle errors explicitly** - never ignore with `_`
- **Return errors, don't panic** (except in truly exceptional cases like initialization)
- **Wrap errors with context** using `fmt.Errorf` with `%w` verb
- Good:
  ```go
  user, err := repo.GetUser(ctx, userID)
  if err != nil {
      return nil, fmt.Errorf("failed to get user %s: %w", userID, err)
  }
  ```
- Bad: `user, _ := repo.GetUser(ctx, userID)` (ignoring errors)
- Bad: `return nil, err` (no context added)
- **Create custom error types** for domain errors
  ```go
  type NotFoundError struct {
      Resource string
      ID       string
  }

  func (e *NotFoundError) Error() string {
      return fmt.Sprintf("%s not found: %s", e.Resource, e.ID)
  }
  ```
- **Check error types** with `errors.Is()` and `errors.As()`

**Pointer Usage**
- **Method receivers**: Use pointer receivers when:
  - Method modifies the receiver
  - Receiver is a large struct (avoid copying)
  - Consistency: if one method uses pointer receiver, all should
- **Function parameters**: Use pointers when:
  - You need to modify the parameter
  - Struct is large (avoid copying)
  - You need to represent "absence" (nil)
- **Return values**: Return pointers when:
  - Returning large structs
  - Need to return nil to indicate absence
  - Database models (common convention)
- **Always check for nil** before dereferencing pointers
- Good:
  ```go
  func (s *UserService) UpdateUser(ctx context.Context, user *User) error {
      if user == nil {
          return ErrUserNil
      }
      // Safe to use user
  }
  ```

**Time Handling**
- **ALWAYS use UTC for timestamps**
- Good: `time.Now().UTC()`
- Bad: `time.Now()` (uses local timezone)
- Store all timestamps in UTC, convert to user's timezone in frontend
- Use `time.Time` not `*time.Time` unless nil is semantically meaningful
- Database: Store as `TIMESTAMPTZ` in PostgreSQL for automatic UTC handling

**Concurrency**
- **Use goroutines** for concurrent operations, but judiciously
- **ALWAYS pass `context.Context`** for cancellation and timeouts
- **Use channels** for communication between goroutines
- Good:
  ```go
  func (s *Service) ProcessBatch(ctx context.Context, items []Item) error {
      errCh := make(chan error, len(items))

      for _, item := range items {
          item := item // Capture loop variable
          go func() {
              errCh <- s.processItem(ctx, item)
          }()
      }

      for i := 0; i < len(items); i++ {
          if err := <-errCh; err != nil {
              return err
          }
      }
      return nil
  }
  ```
- **Use `sync.Mutex`** to protect shared state
- **Use `sync.WaitGroup`** for coordinating goroutines
- **Use `sync.Once`** for one-time initialization
- **Never start goroutines** without a way to stop them (context, channels, or wait groups)

**HTTP Requests**
- **ALWAYS add timeout to `http.Client`** (default 30 seconds)
- **ALWAYS pass `context.Context`** for cancellation
- Good:
  ```go
  client := &http.Client{
      Timeout: 30 * time.Second,
  }

  req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
  if err != nil {
      return nil, fmt.Errorf("failed to create request: %w", err)
  }

  resp, err := client.Do(req)
  if err != nil {
      return nil, fmt.Errorf("request failed: %w", err)
  }
  defer resp.Body.Close()
  ```
- Bad: Using `http.DefaultClient` (no timeout)
- Bad: Not passing context to request
- Use custom timeouts for slow APIs (`Timeout: 60 * time.Second`)

**Dependency Management**
- **Use Go modules** (`go.mod`, `go.sum`)
- **Use `go get package@version`** to add dependencies
- Good: `go get github.com/gin-gonic/gin@v1.9.1`
- **Use `go mod tidy`** to clean up unused dependencies
- **NEVER manually edit `go.sum`** - let Go tools manage it
- Pin versions in production for reproducible builds
- Use `go mod vendor` if vendoring dependencies

**Database Schema Patterns**
- **PRIMARY KEY declaration**: Always use separate `PRIMARY KEY (...)` line at end of table definition
  - Good: `PRIMARY KEY (id)` or `PRIMARY KEY (user_id, gym_id)` as separate line
  - Bad: `id UUID PRIMARY KEY` (inline declaration)
- **UUID generation**: Use `DEFAULT uuid_generate_v4()` for auto-generated UUIDs
  - Good: `gym_id UUID NOT NULL DEFAULT uuid_generate_v4()`
  - Then: `PRIMARY KEY (gym_id)` on separate line
  - Note: Use `DEFAULT`, NOT `GENERATED ALWAYS AS` (uuid_generate_v4 is volatile, not immutable)
  - Always include `NOT NULL` for explicitness (even though PRIMARY KEY implies it)
- **Timestamps**: Use `DEFAULT now()` for auto-timestamps
  - Good: `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`
  - Good: `time TIMESTAMPTZ NOT NULL DEFAULT now()`
  - Prevents API mistakes, ensures database-controlled timestamps
  - Note: Use `DEFAULT`, NOT `GENERATED ALWAYS AS` (now() is volatile, not immutable)
- **User-controlled timestamps**: No default (user sets the value)
  - Good: `last_class TIMESTAMPTZ` (no DEFAULT)
  - Good: `scheduled_date TIMESTAMPTZ` (no DEFAULT)
- **Composite foreign keys**: When table has both `user_id` and `gym_id`, add composite FK
  - Always add: `CONSTRAINT user_gym FOREIGN KEY (user_id, gym_id) REFERENCES user_gym_profiles (user_id, gym_id)`
  - Ensures users can only create records for gyms they belong to

**sqlc Patterns**
- **Co-locate SQL with domains** - Each domain has its own `sql/` subdirectory
- **Write SQL queries in domain sql folder**: `internal/{domain}/sql/queries.sql`
- **Generated code in sql subdirectory** - sqlc generates code in same `sql/` folder
- **Use sqlc annotations** for type-safe code generation:
  - `-- name: GetUser :one` - returns single row
  - `-- name: ListUsers :many` - returns multiple rows
  - `-- name: CreateUser :exec` - executes without return
  - `-- name: CreateUserReturning :one` - executes and returns row
- **Run `sqlc generate`** after adding or modifying queries
- **NEVER manually modify generated code** (`db.go`, `models.go`, `queries.sql.go`)
- **Use `sql.NullString`, `sql.NullInt64`, etc.** for nullable columns
- **Handle transactions** with sqlc's `WithTx()` pattern:
  ```go
  err := db.WithTx(ctx, func(q *Queries) error {
      user, err := q.CreateUser(ctx, params)
      if err != nil {
          return err
      }
      return q.CreateProfile(ctx, profileParams)
  })
  ```
- **ALWAYS pass `context.Context`** to generated query functions
- **Use query parameters (`$1`, `$2`)** not string interpolation
- **Keep SQL queries readable** with proper formatting and indentation
- **Example domain structure with SQL**:
  ```
  internal/user/
  ├── handler.go        # HTTP handlers
  ├── service.go        # Business logic
  ├── repository.go     # Data access (imports ./sql package)
  ├── dto.go            # Request/Response models
  ├── errors.go         # Domain errors
  └── sql/              # SQL queries and generated code
      ├── queries.sql   # SQL queries (YOU write this)
      ├── db.go         # Generated by sqlc (DO NOT EDIT)
      ├── models.go     # Generated by sqlc (DO NOT EDIT)
      └── queries.sql.go # Generated by sqlc (DO NOT EDIT)
  ```
- **Example query file** (`internal/user/sql/queries.sql`):
  ```sql
  -- name: GetUser :one
  SELECT id, email, name, created_at, updated_at
  FROM users
  WHERE id = $1;

  -- name: ListUsers :many
  SELECT id, email, name, created_at, updated_at
  FROM users
  ORDER BY created_at DESC
  LIMIT $1 OFFSET $2;

  -- name: CreateUser :one
  INSERT INTO users (id, email, name, created_at, updated_at)
  VALUES ($1, $2, $3, $4, $5)
  RETURNING id, email, name, created_at, updated_at;
  ```
- **Configure per-domain in sqlc.yaml**:
  ```yaml
  version: "2"
  sql:
    - engine: "postgresql"
      queries: "internal/user/sql"  # Domain sql folder
      schema: "supabase/schemas"    # Supabase schema definitions
      gen:
        go:
          package: "sql"                   # Package name "sql"
          out: "internal/user/sql"  # Generate in domain sql folder
          sql_package: "pgx/v5"
          emit_json_tags: true
          emit_interface: true
  ```
- **Schema location**: Use `supabase/schemas/` directory for database schema definitions
  - sqlc reads table definitions from here to generate type-safe queries
  - Each table should have its own `.sql` file (e.g., `gyms.sql`, `users.sql`)
  - Include CREATE TABLE statements, RLS policies, triggers, and permissions
  - See `llm_context/supabase_sql.md` for schema file patterns
- **Usage in repository**:
  ```go
  import "github.com/yourorg/combatden-api/internal/user/sql"

  type repository struct {
      queries *sql.Queries  // Generated sqlc queries
  }
  ```

## Project Structure

**Domain-Driven Architecture with Co-located SQL**
```
.
├── cmd/
│   └── api/
│       └── main.go              # Application entry point
├── internal/
│   ├── config/
│   │   └── config.go            # Configuration loading
│   ├── database/
│   │   └── postgres.go          # Database connection (optional)
│   ├── domain/
│   │   ├── health/              # Health check domain
│   │   │   └── handler.go
│   │   ├── user/                # User domain (self-contained)
│   │   │   ├── handler.go       # HTTP handlers (Gin)
│   │   │   ├── service.go       # Business logic
│   │   │   ├── repository.go    # Data access (imports ./sql)
│   │   │   ├── dto.go           # Request/Response structs
│   │   │   ├── errors.go        # Domain-specific errors
│   │   │   └── sql/             # SQL queries and generated code
│   │   │       ├── queries.sql  # SQL queries (YOU write)
│   │   │       ├── db.go        # Generated by sqlc (DO NOT EDIT)
│   │   │       ├── models.go    # Generated by sqlc (DO NOT EDIT)
│   │   │       └── queries.sql.go # Generated by sqlc (DO NOT EDIT)
│   │   └── post/                # Post domain (same structure)
│   │       ├── handler.go
│   │       ├── service.go
│   │       ├── repository.go
│   │       ├── dto.go
│   │       ├── errors.go
│   │       └── sql/             # SQL queries and generated code
│   │           ├── queries.sql
│   │           ├── db.go
│   │           ├── models.go
│   │           └── queries.sql.go
│   ├── middleware/              # Gin middleware
│   │   ├── auth.go              # Supabase JWT validation
│   │   ├── cors.go              # CORS configuration
│   │   ├── logging.go           # Request logging
│   │   ├── recovery.go          # Panic recovery
│   │   └── security.go          # Security headers
│   ├── logger/                  # Application logger
│   │   └── logger.go
│   └── router/
│       └── router.go            # Route registration
├── supabase/
│   └── schemas/                 # Database schema definitions
│       ├── gyms.sql             # Gym table schema, RLS, triggers
│       └── users.sql            # User table schema (example)
├── llm_context/                 # LLM reference documentation
│   └── supabase_sql.md          # Supabase SQL patterns
├── sqlc.yaml                    # sqlc configuration (one entry per domain)
├── .golangci.yml                # Linter configuration
├── Makefile                     # Build and development commands
├── go.mod
└── go.sum
```

**Why Domain-Driven with Co-located SQL**
- Clear boundaries between business domains
- Easy to scale and maintain
- Teams can work independently on different domains
- Promotes separation of concerns
- Each domain is self-contained: handlers, services, repositories, DTOs, and SQL
- SQL queries live with the domain code that uses them
- Generated SQL code is isolated in `sql/` subdirectory for clarity

**sqlc Integration**
- Each domain has its own `sql/` subdirectory with queries and generated code
- SQL queries: `internal/{domain}/sql/queries.sql`
- Generated code: `internal/{domain}/sql/*.go`
- Database schema: `supabase/schemas/` (shared across domains)
- Configuration: One entry per domain in `sqlc.yaml`
- Run `sqlc generate` to regenerate all domain SQL code

**Directory Conventions**
- `cmd/`: Application entry points (one directory per executable, keep thin)
- `internal/`: Private application code (Go compiler prevents external imports)
  - Use for ALL application-specific code
  - `internal/{domain}/`: Self-contained domain packages
  - `internal/{domain}/sql/`: SQL queries and generated code per domain
  - `internal/logger/`, `internal/middleware/`, etc.: Shared utilities
- `supabase/schemas/`: Database schema definitions (CREATE TABLE, RLS, triggers, permissions)
  - Used by sqlc to generate type-safe queries
  - One file per table (e.g., `gyms.sql`, `users.sql`)
- `llm_context/`: LLM reference documentation (not part of build)
- `pkg/`: Public libraries **only if** you want other projects to import them
  - Most projects don't need this directory
  - Only create when building reusable libraries

## Gin Patterns

**Dependency Injection**
- **Use struct fields** to hold dependencies
- **Pass dependencies via constructors** for initialization
- **Use interfaces** for testability and flexibility
- Good:
  ```go
  type UserHandler struct {
      service UserService
      logger  logger.Logger
  }

  func NewUserHandler(service UserService, logger logger.Logger) *UserHandler {
      return &UserHandler{
          service: service,
          logger:  logger,
      }
  }

  func (h *UserHandler) GetUser(c *gin.Context) {
      // Use h.service and h.logger
  }
  ```
- **Wire dependencies in `main.go`**:
  ```go
  func main() {
      db := database.Connect()
      logger := logger.New()

      userRepo := user.NewRepository(db)
      userService := user.NewService(userRepo)
      userHandler := user.NewHandler(userService, logger)

      router := setupRouter(userHandler)
      router.Run(":8080")
  }
  ```

**Router Organization**
- **One handler per domain/resource**
- **Use RESTful principles** with proper HTTP methods
- **Use `gin.RouterGroup`** for versioning and grouping
- **Plural nouns for resources** (`/users`, not `/user`)
- **Path parameters for IDs**, query parameters for filters
- **Proper HTTP status codes** using Gin constants
- Good:
  ```go
  func SetupRouter(userHandler *user.Handler, postHandler *post.Handler) *gin.Engine {
      r := gin.Default()

      v1 := r.Group("/api/v1")
      {
          users := v1.Group("/users")
          {
              users.GET("", userHandler.List)        // 200
              users.GET("/:id", userHandler.Get)     // 200, 404
              users.POST("", userHandler.Create)     // 201, 400
              users.PUT("/:id", userHandler.Update)  // 200, 400, 404
              users.DELETE("/:id", userHandler.Delete) // 204, 404
          }

          posts := v1.Group("/posts")
          {
              posts.GET("", postHandler.List)
              posts.POST("", postHandler.Create)
          }
      }

      return r
  }
  ```
- **HTTP Status Codes**:
  - `200 OK`: Successful GET, PUT
  - `201 Created`: Successful POST (resource created)
  - `204 No Content`: Successful DELETE
  - `400 Bad Request`: Validation error
  - `401 Unauthorized`: Missing or invalid authentication
  - `403 Forbidden`: Authenticated but not authorized
  - `404 Not Found`: Resource not found
  - `500 Internal Server Error`: Server error

**Request/Response Models (DTOs)**
- **Use structs with JSON and validation tags**
- **Separate DTOs for create, update, and response**
- **Use `binding:"required"` for required fields**
- **Use pointer fields for optional values** in update DTOs
- **Omit sensitive fields** in response structs
- Good:
  ```go
  // Create DTO - all required fields
  type CreateUserRequest struct {
      Email    string `json:"email" binding:"required,email"`
      Name     string `json:"name" binding:"required,min=2,max=100"`
      Password string `json:"password" binding:"required,min=8"`
  }

  // Update DTO - all fields optional (pointers)
  type UpdateUserRequest struct {
      Name  *string `json:"name,omitempty" binding:"omitempty,min=2,max=100"`
      Email *string `json:"email,omitempty" binding:"omitempty,email"`
  }

  // Response DTO - exclude sensitive fields
  type UserResponse struct {
      ID        string    `json:"id"`
      Email     string    `json:"email"`
      Name      string    `json:"name"`
      CreatedAt time.Time `json:"created_at"`
      UpdatedAt time.Time `json:"updated_at"`
      // Password intentionally omitted
  }
  ```
- **Use `validator` package** for complex validation
- **Bind and validate in handlers**:
  ```go
  func (h *UserHandler) Create(c *gin.Context) {
      var req CreateUserRequest
      if err := c.ShouldBindJSON(&req); err != nil {
          c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
          return
      }
      // Process validated request
  }
  ```

**Error Handling**
- **Create custom error types** implementing `error` interface
- **Use middleware** for consistent error responses
- **Log errors at handler level**, return errors from service/repository
- **Use Gin's `c.JSON()`** with appropriate status codes
- Good:
  ```go
  // Custom error types
  type NotFoundError struct {
      Resource string
      ID       string
  }

  func (e *NotFoundError) Error() string {
      return fmt.Sprintf("%s not found: %s", e.Resource, e.ID)
  }

  // Handler error handling
  func (h *UserHandler) Get(c *gin.Context) {
      userID := c.Param("id")

      user, err := h.service.GetUser(c.Request.Context(), userID)
      if err != nil {
          var notFoundErr *NotFoundError
          if errors.As(err, &notFoundErr) {
              c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
              return
          }
          h.logger.Error("Failed to get user", "error", err, "user_id", userID)
          c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
          return
      }

      c.JSON(http.StatusOK, user)
  }
  ```
- **Error response middleware**:
  ```go
  func ErrorHandler() gin.HandlerFunc {
      return func(c *gin.Context) {
          c.Next()

          if len(c.Errors) > 0 {
              err := c.Errors.Last()
              // Handle different error types and return appropriate responses
          }
      }
  }
  ```

**Logging and Exception Strategy**
- **Handler layer**: Log errors with context before returning HTTP responses
  - Good: `h.logger.Error("Failed to create user", "error", err, "email", req.Email)`
  - Always include relevant context (user IDs, request parameters, etc.)
  - Use structured logging (key-value pairs)
- **Service/Repository layers**: Return errors with context using `fmt.Errorf`
  - Good: `return fmt.Errorf("failed to create user: %w", err)`
  - Focus on clear, descriptive error messages
  - Don't log in service/repository - let handler layer decide
- **Layer Separation**: Handlers log + respond, Services/Repositories return errors

**Middleware**
- **One purpose per middleware**
- **Proper ordering** (order matters in Gin):
  1. Recovery (panic recovery)
  2. CORS
  3. Logging
  4. Authentication
  5. Rate Limiting
- **Use `gin.HandlerFunc` type**:
  ```go
  func AuthMiddleware(supabase *supabase.Client) gin.HandlerFunc {
      return func(c *gin.Context) {
          token := extractToken(c)
          if token == "" {
              c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Missing token"})
              return
          }

          user, err := supabase.Auth.User(c.Request.Context(), token)
          if err != nil {
              c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Invalid token"})
              return
          }

          c.Set("user", user)
          c.Next()
      }
  }
  ```
- **Apply middleware** at router or group level:
  ```go
  r := gin.Default() // Includes Recovery and Logger middleware
  r.Use(CORSMiddleware())

  protected := r.Group("/api/v1")
  protected.Use(AuthMiddleware(supabase))
  {
      protected.GET("/profile", profileHandler.Get)
  }
  ```

## Database Patterns

**sqlc Patterns**
- **Write SQL queries** in `.sql` files organized by domain
- **Use sqlc annotations** for code generation:
  - `:one` - Returns single row or error
  - `:many` - Returns slice of rows
  - `:exec` - Executes query, returns error only
  - `:execrows` - Returns rows affected
- **Generate type-safe code** with `sqlc generate`
- **NEVER modify generated code** - regenerate instead
- **Handle NULL values** with `sql.Null*` types:
  ```go
  type User struct {
      ID        uuid.UUID
      Email     string
      Name      sql.NullString  // Can be NULL in database
      Bio       sql.NullString
      CreatedAt time.Time
  }
  ```
- **Use transactions** with `WithTx()` pattern:
  ```sql
  -- name: TransferFunds :exec
  UPDATE accounts SET balance = balance - $1 WHERE id = $2;
  ```
  ```go
  err := db.WithTx(ctx, func(q *Queries) error {
      if err := q.TransferFunds(ctx, amount, fromID); err != nil {
          return err
      }
      return q.TransferFunds(ctx, -amount, toID)
  })
  ```

**Repository Pattern**
- **Separate data access from business logic**
- **One repository per domain** wrapping sqlc queries
- **Define repository interface** for testability
- **Methods**: `Get`, `List`, `Create`, `Update`, `Delete`
- **ALWAYS pass `context.Context`** to all database operations
- Good:
  ```go
  type UserRepository interface {
      Get(ctx context.Context, id string) (*User, error)
      List(ctx context.Context, limit, offset int) ([]*User, error)
      Create(ctx context.Context, user *User) error
      Update(ctx context.Context, user *User) error
      Delete(ctx context.Context, id string) error
  }

  type userRepository struct {
      queries *database.Queries
  }

  func NewUserRepository(queries *database.Queries) UserRepository {
      return &userRepository{queries: queries}
  }

  func (r *userRepository) Get(ctx context.Context, id string) (*User, error) {
      dbUser, err := r.queries.GetUser(ctx, uuid.MustParse(id))
      if err != nil {
          if errors.Is(err, sql.ErrNoRows) {
              return nil, &NotFoundError{Resource: "user", ID: id}
          }
          return nil, fmt.Errorf("failed to get user: %w", err)
      }
      return toUser(dbUser), nil
  }
  ```

**Supabase for Simple Operations**
- **Use Supabase Go client** for basic CRUD when appropriate
- **Auth-related operations** should use Supabase (signup, login, session management)
- **Simple single-table queries** can use Supabase client
- **Complex queries, joins, transactions** should use sqlc
- Good Supabase use cases:
  - User authentication and session management
  - Simple CRUD on single tables
  - Real-time subscriptions
  - Storage operations (file uploads)
- Use sqlc for:
  - Complex queries with joins
  - Transactions across multiple tables
  - Custom SQL logic
  - Performance-critical queries

**Supabase Database Security**
- **See `llm_context/supabase_sql.md`** for detailed patterns on:
  - Row Level Security (RLS) policies
  - Column-level permissions
  - Database triggers for automatic row creation
  - UUID primary keys
- **ALWAYS enable RLS** on tables with user data
- **ALWAYS revoke UPDATE** on immutable columns (IDs, owner_id, created_at)
- **Use triggers** to automatically create related records (e.g., user profiles on signup)

**Service Layer**
- **Contains business logic and validation**
- **Orchestrates repository calls**
- **Handles transactions** via sqlc `WithTx()` or repository methods
- **Validates business rules** before database operations
- **Returns DTOs**, not database models
- **Uses repository interfaces** for testability
- Good:
  ```go
  type UserService interface {
      GetUser(ctx context.Context, id string) (*UserResponse, error)
      CreateUser(ctx context.Context, req *CreateUserRequest) (*UserResponse, error)
      UpdateUser(ctx context.Context, id string, req *UpdateUserRequest) (*UserResponse, error)
  }

  type userService struct {
      repo UserRepository
  }

  func NewUserService(repo UserRepository) UserService {
      return &userService{repo: repo}
  }

  func (s *userService) CreateUser(ctx context.Context, req *CreateUserRequest) (*UserResponse, error) {
      // Validate business rules
      if err := s.validateEmail(req.Email); err != nil {
          return nil, err
      }

      // Create user via repository
      user := &User{
          ID:    uuid.New().String(),
          Email: req.Email,
          Name:  req.Name,
      }

      if err := s.repo.Create(ctx, user); err != nil {
          return nil, fmt.Errorf("failed to create user: %w", err)
      }

      return toUserResponse(user), nil
  }
  ```

**Layer Separation**
- **Handler → Service → Repository → Database (sqlc/Supabase)**
- **Handler** handles HTTP concerns (parsing requests, validation, response formatting)
- **Service** handles business logic (validation, orchestration, transactions)
- **Repository** handles data access (wraps sqlc queries or Supabase calls)
- **NEVER skip layers** - even if it seems simpler
- Benefits: Testability, maintainability, clear separation of concerns

## Testing

**Test Structure**
- **Use Go's `testing` package** - standard library
- **Use `testify/assert` and `testify/mock`** for assertions and mocking
- **Table-driven tests** for testing multiple cases
- **One `_test.go` file** per package (same package as code)
- **Test files in same directory** as source files
- Good:
  ```go
  package user

  import (
      "testing"

      "github.com/stretchr/testify/assert"
  )

  func TestUserService_CreateUser(t *testing.T) {
      tests := []struct {
          name    string
          input   *CreateUserRequest
          want    *UserResponse
          wantErr bool
      }{
          {
              name: "valid user",
              input: &CreateUserRequest{Email: "test@example.com", Name: "Test"},
              want: &UserResponse{Email: "test@example.com", Name: "Test"},
              wantErr: false,
          },
          {
              name: "invalid email",
              input: &CreateUserRequest{Email: "invalid", Name: "Test"},
              wantErr: true,
          },
      }

      for _, tt := range tests {
          t.Run(tt.name, func(t *testing.T) {
              got, err := service.CreateUser(context.Background(), tt.input)
              if tt.wantErr {
                  assert.Error(t, err)
                  return
              }
              assert.NoError(t, err)
              assert.Equal(t, tt.want.Email, got.Email)
          })
      }
  }
  ```

**Test Types**
- **Unit tests** for service layer (mock repositories)
- **Integration tests** for handlers (using `httptest`)
- **Test error conditions** (nil pointers, validation errors, database errors)
- **Test validation rules** (required fields, format validation)
- **Test authentication/authorization** (valid tokens, expired tokens, unauthorized access)
- Handler integration test example:
  ```go
  func TestUserHandler_Create(t *testing.T) {
      gin.SetMode(gin.TestMode)

      mockService := new(MockUserService)
      handler := NewUserHandler(mockService, logger.NewNoop())

      router := gin.New()
      router.POST("/users", handler.Create)

      req := CreateUserRequest{Email: "test@example.com", Name: "Test"}
      body, _ := json.Marshal(req)

      w := httptest.NewRecorder()
      httpReq, _ := http.NewRequest("POST", "/users", bytes.NewBuffer(body))
      httpReq.Header.Set("Content-Type", "application/json")

      router.ServeHTTP(w, httpReq)

      assert.Equal(t, http.StatusCreated, w.Code)
  }
  ```

**Coverage**
- **Use `go test -cover`** for coverage reports
- **Use `go test -coverprofile=coverage.out`** for detailed reports
- **View HTML coverage**: `go tool cover -html=coverage.out`
- **Aim for 80%+ code coverage**
- Focus on critical business logic
- Test happy paths and error cases

## Security

**Authentication & Authorization**
- **Use Supabase for authentication** (user signup, login, password management)
- **Validate Supabase JWT tokens in middleware**
- **Extract user information from JWT claims**
- **Use Supabase client** for user management operations
- **Implement RBAC** using Supabase roles and user metadata
- Example auth middleware:
  ```go
  func SupabaseAuthMiddleware(supabase *supabase.Client) gin.HandlerFunc {
      return func(c *gin.Context) {
          // Extract token from Authorization header
          token := c.GetHeader("Authorization")
          if token == "" {
              c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Missing authorization token"})
              return
          }

          // Remove "Bearer " prefix
          token = strings.TrimPrefix(token, "Bearer ")

          // Validate token with Supabase
          user, err := supabase.Auth.User(c.Request.Context(), token)
          if err != nil {
              c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Invalid token"})
              return
          }

          // Attach user to context
          c.Set("user_id", user.ID)
          c.Set("user_email", user.Email)
          c.Next()
      }
  }
  ```
- **Role-based access control**:
  ```go
  func RequireRole(role string) gin.HandlerFunc {
      return func(c *gin.Context) {
          userRole, _ := c.Get("user_role")
          if userRole != role {
              c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "Insufficient permissions"})
              return
          }
          c.Next()
      }
  }
  ```

**Input Validation**
- **Use `validator` package** with struct tags
- **Bind and validate** in handlers with `c.ShouldBindJSON()`
- **Sanitize HTML content** before storing (use `bluemonday` package)
- **Use parameterized queries** (sqlc does this automatically)
- **Validate file uploads** (size, type, content)
- Example validation tags:
  ```go
  type CreatePostRequest struct {
      Title   string `json:"title" binding:"required,min=3,max=200"`
      Content string `json:"content" binding:"required,max=10000"`
      Tags    []string `json:"tags" binding:"max=10,dive,min=2,max=50"`
  }
  ```

**Configuration**
- **ALL configuration MUST go in `internal/config/` package**
  - Single source of truth for all application configuration
  - Never create separate config files in other packages (database, middleware, etc.)
  - All config structs and types belong in `internal/config/config.go`
  - Other packages import and use `config.Config` or specific config types
- **Environment variables for all secrets**:
  - `SUPABASE_URL` - Supabase project URL
  - `SUPABASE_ANON_KEY` - Supabase anonymous key (for client-side)
  - `SUPABASE_SERVICE_KEY` - Supabase service role key (for server-side)
  - `DATABASE_URL` - PostgreSQL connection string
  - `JWT_SECRET` - Additional JWT secret if needed
- **Configuration structure pattern**:
  ```go
  // In internal/config/config.go
  type Config struct {
      ServerPort string
      ServerHost string
      Env        Environment

      // Group related config into sub-structs
      Database DatabaseConfig
      Supabase SupabaseConfig
  }

  type DatabaseConfig struct {
      URL               string
      MaxConns          int32
      MinConns          int32
      MaxConnLifetime   time.Duration
      MaxConnIdleTime   time.Duration
      HealthCheckPeriod time.Duration
  }
  ```
- **Usage in other packages**:
  ```go
  // In internal/database/postgres.go
  import "github.com/yourorg/combatden-api/internal/config"

  func New(ctx context.Context, url string, cfg config.DatabaseConfig) (*DB, error) {
      // Use cfg.MaxConns, cfg.MinConns, etc.
  }
  ```
- **CORS configuration**:
  - Specific origins only in production (include Supabase domains)
  - `Access-Control-Allow-Credentials: true` for Supabase
- **Rate limiting middleware** on public endpoints
- **Security headers middleware**:
  ```go
  func SecurityHeaders() gin.HandlerFunc {
      return func(c *gin.Context) {
          c.Header("X-Content-Type-Options", "nosniff")
          c.Header("X-Frame-Options", "DENY")
          c.Header("X-XSS-Protection", "1; mode=block")
          c.Header("Strict-Transport-Security", "max-age=31536000")
          c.Next()
      }
  }
  ```
- **HTTPS only in production**

## Documentation

**Code Documentation**
- **Godoc comments** for all exported functions, types, methods, and packages
- **Comment format**: `// FunctionName does something` (starts with name)
- **Package documentation** in `doc.go` or at top of main file
- Good:
  ```go
  // Package user provides user management functionality including
  // creation, retrieval, and updates of user accounts.
  package user

  // UserService defines operations for managing users.
  type UserService interface {
      // GetUser retrieves a user by ID.
      // Returns NotFoundError if user doesn't exist.
      GetUser(ctx context.Context, id string) (*UserResponse, error)
  }

  // NewUserService creates a new user service with the given repository.
  func NewUserService(repo UserRepository) UserService {
      return &userService{repo: repo}
  }
  ```
- **Document parameters, return values, errors** in complex functions
- **Keep documentation updated** with code changes

**API Documentation**
- **Use Swagger/OpenAPI** with `swaggo/swag`
- **Add annotations** above handler functions
- **Generate docs** with `swag init`
- **Serve docs** with Gin middleware
- Good:
  ```go
  // @Summary Create a new user
  // @Description Create a new user account with the provided information
  // @Tags users
  // @Accept json
  // @Produce json
  // @Param user body CreateUserRequest true "User creation request"
  // @Success 201 {object} UserResponse
  // @Failure 400 {object} ErrorResponse
  // @Failure 500 {object} ErrorResponse
  // @Router /api/v1/users [post]
  func (h *UserHandler) Create(c *gin.Context) {
      // Implementation
  }
  ```
- **Serve Swagger UI**:
  ```go
  import "github.com/swaggo/gin-swagger"

  r.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))
  ```
- **Document all possible status codes**
- **Use tags to organize endpoints** by domain

**Versioning**
- **Use router groups** for API versions
- Good:
  ```go
  v1 := r.Group("/api/v1")
  {
      v1.GET("/users", userHandlerV1.List)
  }

  v2 := r.Group("/api/v2")
  {
      v2.GET("/users", userHandlerV2.List)
  }
  ```
- **Maintain separate handlers** per version if needed
- **Document breaking changes** in CHANGELOG
- **Provide migration guides** when releasing new versions

## Code Quality Checklist

- [ ] Follows SOLID principles
- [ ] All errors handled explicitly (no `_` ignoring errors)
- [ ] Proper context propagation (`context.Context` passed through layers)
- [ ] Domain-driven structure followed
- [ ] Repository pattern for data access
- [ ] Service layer for business logic
- [ ] Input validation with `validator` package
- [ ] Custom error types for domain errors
- [ ] Comprehensive tests with good coverage
- [ ] Security best practices (auth, validation, parameterized queries)
- [ ] Complete Godoc documentation for exported items
- [ ] No secrets in code (use environment variables)
- [ ] Proper error messages with context
- [ ] Code formatted with `gofmt`/`goimports`
- [ ] All linter warnings addressed

## Linting

**IMPORTANT: Always run linters after making code changes**

**golangci-lint**
- **Run `golangci-lint run`** before committing
- **Configure in `.golangci.yml`**
- **Enable recommended linters**:
  - `gofmt` - formatting
  - `goimports` - import formatting
  - `govet` - suspicious constructs
  - `errcheck` - unchecked errors
  - `staticcheck` - static analysis
  - `gosec` - security issues
  - `ineffassign` - ineffectual assignments
  - `unused` - unused code
- **Fix all errors and warnings**
- Example `.golangci.yml`:
  ```yaml
  linters:
    enable:
      - gofmt
      - goimports
      - govet
      - errcheck
      - staticcheck
      - gosec
      - ineffassign
      - unused
      - misspell

  linters-settings:
    govet:
      check-shadowing: true
    gofmt:
      simplify: true
  ```

**Other Tools**
- **`go vet`**: Built-in static analysis (`go vet ./...`)
- **`gofmt`**: Format code (`gofmt -w .`)
- **`goimports`**: Organize imports (`goimports -w .`)
- **`go test`**: Run tests (`go test -v ./...`)
- **`go test -race`**: Detect race conditions

**Makefile Commands**
```makefile
.PHONY: lint fmt test

lint:
	golangci-lint run
	go vet ./...

fmt:
	gofmt -w .
	goimports -w .

test:
	go test -v -race -cover ./...

sqlc:
	sqlc generate
```

**Remember: Code is read more often than written. Prioritize clarity, modularity, and maintainability.**

## Codebase Overview

**IMPORTANT: Only update this section for major architectural changes:**
- Adding a new domain (e.g., new directory in `internal/`)
- Major restructuring of existing domains
- Adding new supporting directories with significant purpose
- Changing core request flows or architecture patterns

**Keep descriptions high-level and implementation-agnostic:**
- Focus on WHAT each domain does, not HOW it does it
- Avoid mentioning specific libraries, tools, or implementation details
- Don't document individual functions, structs, or files
- Keep it brief - this is an overview, not detailed documentation

**Template: Update the sections below based on your actual Go project structure**

### Core Domains

**`internal/auth/`** - Authentication Domain
- User authentication and authorization
- JWT token validation and management
- Session handling

**`internal/user/`** - User Management
- User profile management
- User preferences and settings

### Supporting Packages

**`internal/config/`** - Configuration
- Application configuration loading
- Environment variable management

**`internal/database/`** - Data Persistence
- PostgreSQL connection management
- sqlc generated queries (type-safe SQL)
- Database migrations

**`internal/middleware/`** - HTTP Middleware
- Request logging
- Authentication verification
- CORS and security headers

**`internal/logger/`** - Logging
- Structured logging utilities
- Log level configuration

### Request Flow

**Typical API Request:** HTTP Request → Middleware (CORS, Auth, Logging) → Handler (validation) → Service (business logic) → Repository (data access) → Database
