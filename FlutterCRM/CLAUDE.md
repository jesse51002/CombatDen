# Flutter-Squillo Coding Standards

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## General Principles

**SOLID Principles**
- Single Responsibility: Each widget/class has one well-defined purpose
- Open/Closed: Open for extension, closed for modification
- Liskov Substitution: Subtypes must be substitutable for their base types
- Interface Segregation: Many specific interfaces over one general-purpose
- Dependency Inversion: Depend on abstractions, not concretions

**Other Core Principles**
- DRY (Don't Repeat Yourself): Single source of truth for each piece of logic
- KISS (Keep It Simple): Favor simplicity over complexity
- YAGNI (You Aren't Gonna Need It): Don't add features until needed
- Separation of Concerns: Separate UI, business logic, and data layers

## API Reference

**OpenAPI Specification**
- **ALWAYS reference `openapi.json`** when working with API models and endpoints
- The OpenAPI spec defines the complete backend API contract
- Use this as the source of truth for:
  - Data models and their structure
  - API endpoint paths and methods
  - Request/response schemas
  - Enum values and validation rules
- Update models when API spec changes: `make update-openapi`

## Backend & Database

**Supabase Integration**
- **We are using Supabase** as our backend-as-a-service platform
- Supabase provides:
  - PostgreSQL database with real-time subscriptions
  - Authentication and authorization
  - Row-level security (RLS) policies
  - Storage for files and media
  - Edge functions for serverless compute

**Supabase Best Practices**
- Use `supabase_flutter` package for all Supabase interactions
- Initialize Supabase client in `main.dart` before app starts
- Store Supabase URL and anon key in environment variables (`.env`)
- Never commit Supabase service role key or secrets
- Use repositories to abstract Supabase data sources
- Leverage RLS policies for security - don't bypass them
- Use Supabase real-time subscriptions for live data updates
- Handle Supabase auth state changes through AuthBloc

**Repository Pattern with Supabase**
- Repository layer wraps Supabase client calls
- Convert Supabase responses to domain models
- Handle Supabase errors and convert to custom exceptions
- Example:
  ```dart
  class UserRepository {
    final SupabaseClient _supabase;

    Future<User> getUserById(String id) async {
      try {
        final response = await _supabase
          .from('users')
          .select()
          .eq('id', id)
          .single();
        return User.fromJson(response);
      } on PostgrestException catch (e) {
        throw DatabaseException(e.message);
      }
    }
  }
  ```

## Development Commands

### API Management
- `make update-openapi` - Fetch latest OpenAPI spec from local backend (http://localhost:8000)
- Requires backend server running on localhost:8000

### Building and Running
- `flutter run` - Run the app in debug mode (hot reload enabled)
- `flutter run --release` - Run the app in release mode
- `flutter build apk` - Build Android APK
- `flutter build ios` - Build for iOS (requires macOS and Xcode)

### Development Tools
- `flutter analyze` - Run static analysis and linting
- `flutter test` - Run all tests
- `flutter test test/widget_test.dart` - Run specific test file
- `flutter pub get` - Install dependencies
- `flutter pub upgrade` - Upgrade dependencies
- `flutter clean` - Clean build artifacts

## Dart Standards

**Imports**
- **ALWAYS use package imports** - never use relative imports
- Good: `import 'package:app_name/features/auth/bloc/auth_bloc.dart';`
- Bad: `import '../bloc/auth_bloc.dart';`
- Bad: `import './auth_bloc.dart';`

**Naming Conventions**
- Files/packages: `auth_bloc.dart`, `user_repository.dart`
- Classes: `AuthBloc`, `UserRepository`
- Functions/variables: `getUserById`, `userCount`
- Constants: `kMaxConnections`, `kApiTimeout`
- Private: `_internalVar`, `_privateMethod`
- Blocs: `FeatureBloc`, `FeatureEvent`, `FeatureState`

**Formatting**
- Max 80 characters per line
- Use `dart format` for consistent formatting
- Trailing commas for better diffs

**Type Hints**
- Always use type annotations for function parameters and return values
- Use generics appropriately (`List<String>`, `Map<String, int>`)
- Use nullable types with `?` for optional values
- Create type aliases for complex types

**Code Complexity & Nesting**
- **Limit deep nesting**
- **Extract methods when nesting gets complex** - create helper methods
- **Once nesting starts getting deep, separate it out**:
  - Create a new function widget in the same file for related UI logic
  - Move to a different file if the widget becomes reusable or substantial
- Good: Extract nested logic into separate, well-named private methods or widgets
- Bad: Deep nesting makes code hard to read and maintain

**DateTime Handling**
- Use local timezone for UI display and local operations
- **Convert to UTC when sending to backend**
- Good: `DateTime.now()` for local use, `.toUtc()` for API requests
- Backend stores UTC, frontend converts to local for display

**HTTP Requests**
- **ALWAYS add timeout to HTTP requests (default to 30 seconds)**
- Good: `dio.get(url, options: Options(receiveTimeout: Duration(seconds: 30)))`
- Bad: HTTP requests without timeout (can hang indefinitely)
- Use custom timeouts for specific endpoints if needed

**Screen Layout**
- **Use consistent horizontal padding** on all screens
- Use `DesignConstants.screenHorizontalPadding` for all screen-level horizontal padding
- Good: `Padding(padding: EdgeInsets.symmetric(horizontal: DesignConstants.screenHorizontalPadding))`
- This ensures visual consistency across all screens in the app

## Screen Architecture & Widget Separation

**Screens as Widget Composition**
- **Screens are collections of smaller, focused widgets** - not monolithic build methods
- Break complex screens into logical sections (e.g., `IngredientsSection`, `TechniquesSection`, `InfoBadgesGrid`)
- Each section widget has a single, clear responsibility
- This improves readability, testability, and maintainability

**Widget Separation Guidelines**
- **When to extract to a separate widget file**:
  - Widget becomes substantial (>50-100 lines)
  - Widget is reusable across different screens or features
  - Widget has complex internal state or logic
  - Widget represents a distinct UI component (e.g., `TechniqueCard`, `IngredientCheckboxItem`)
- **When to use private helper methods** (`_buildSection()`):
  - Small UI pieces within the same screen (<30 lines)
  - UI logic tightly coupled to the parent widget's state
  - One-off UI elements not used elsewhere
- **Widget file organization**:
  - Feature-specific widgets → `features/[feature]/presentation/widgets/`
  - Reusable components → `shared/widgets/`
  - One widget per file for clarity

**Widget Naming Conventions**
- Use clear, descriptive names that indicate purpose
- Section widgets: `[Content]Section` (e.g., `IngredientsSection`, `HeaderSection`)
- Item widgets: `[Item]Card`, `[Item]Tile`, `[Item]Item` (e.g., `TechniqueCard`, `RecipeListTile`, `IngredientCheckboxItem`)
- Grid/List widgets: `[Content]Grid`, `[Content]List` (e.g., `InfoBadgesGrid`, `RecipesList`)
- Avoid generic names like `CustomWidget`, `MyWidget`, `WidgetOne`

**BLoC Integration in Widgets**
- **Widgets dispatch events to BLoC** - never call methods directly
- **Widgets listen to state changes** - use `BlocBuilder`, `BlocListener`, `BlocConsumer`
- **NO callbacks for business logic** - use BLoC events instead
- Good: `context.read<RecipeDetailBloc>().add(ToggleIngredientChecked(index))`
- Bad: Passing `onToggle: () { /* business logic */ }` callbacks through widget layers
- Callbacks acceptable for: simple UI interactions (button onTap), form field onChange

**Optimistic UI Updates Pattern**
- For actions that sync with server (e.g., toggling checkboxes):
  - Step 1: Update UI immediately (optimistic update)
  - Step 2: Mark as syncing/loading (disable further interaction)
  - Step 3: Send request to server
  - Step 4: On success - clear loading state; On error - revert to previous state
- Benefits: Immediate user feedback, better perceived performance
- Implementation: Use state flags like `isSyncing`, `isLoading` in your models

**Example Screen Structure**
```dart
class RecipeDetailScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RecipeDetailBloc, RecipeDetailState>(
      builder: (context, state) {
        if (state is RecipeDetailLoading) {
          return LoadingWidget();
        }
        if (state is RecipeDetailError) {
          return ErrorWidget(message: state.message);
        }
        if (state is RecipeDetailLoaded) {
          return SingleChildScrollView(
            child: Column(
              children: [
                HeaderSection(recipe: state.recipe),
                IngredientsSection(ingredients: state.ingredients),
                TechniquesSection(techniques: state.simplifiedTechniques),
                InfoBadgesGrid(recipe: state.recipe),
              ],
            ),
          );
        }
        return Container();
      },
    );
  }
}

// Separate file: ingredients_section.dart
class IngredientsSection extends StatelessWidget {
  final List<IngredientWithState> ingredients;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: ingredients.map((ing) =>
        IngredientCheckboxItem(ingredientState: ing, index: i)
      ).toList(),
    );
  }
}

// Separate file: ingredient_checkbox_item.dart
class IngredientCheckboxItem extends StatelessWidget {
  final IngredientWithState ingredientState;
  final int index;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        context.read<RecipeDetailBloc>().add(
          ToggleIngredientChecked(index),
        );
      },
      child: _buildCheckboxRow(),
    );
  }

  Widget _buildCheckboxRow() {
    // Small helper method for internal UI structure
    return Row(...);
  }
}
```

## Theming System

**CRITICAL: ALWAYS Use DesignConstants**
- **EVERY widget MUST import and use `package:flutter_crm/core/constants/design_constants.dart`**
- **NEVER use default colors** (e.g., `Colors.red`, `Colors.blue`, `Color(0xFF...)` hardcoded values)
- **NEVER use default fonts** (e.g., hardcoded `fontFamily`, default text styles)
- **NEVER create new design constants without explicit permission** - Always ask first before adding new colors, text styles, or design values
- **ALWAYS reference DesignConstants** for:
  - All colors: `DesignConstants.primaryColor`, `DesignConstants.text`, etc.
  - All text styles: `DesignConstants.h1`, `DesignConstants.h2`, `DesignConstants.p`, etc.
  - All design values: `DesignConstants.buttonBorder`, spacing, radii, etc.
- Good: `color: DesignConstants.primaryColor`, `style: DesignConstants.h2`
- Bad: `color: Colors.orange`, `color: Color(0xFFFF6C2D)`, `fontSize: 16`
- This ensures consistent theming across the entire app

**Architecture**: DesignConstants + Material 3 ColorScheme + Custom Widgets

**DesignConstants** (`lib/core/constants/design_constants.dart`)
- Single source of truth for all design values
- Colors: primary, secondary, background, text, and opacity variations
- Design values: radiusBig (16), buttonBorderSize (3)
- Can be inherited for theme variations (e.g., light theme, brand variations)

**AppTheme** (`lib/shared/themes/app_theme.dart`)
- ThemeData configuration with Material 3 enabled
- ColorScheme references DesignConstants for consistency
- Pre-configured component themes (buttons, inputs, cards)

**Usage in Widgets**:
```dart
import 'package:flutter_crm/core/constants/design_constants.dart';

// Access colors and design values directly
Container(
  color: DesignConstants.primary,
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(DesignConstants.radiusBig),
    border: Border.all(
      color: DesignConstants.buttonStroke,
      width: DesignConstants.buttonBorderSize,
    ),
  ),
)

// Material widgets are auto-themed via ColorScheme
ElevatedButton(...) // Uses DesignConstants.primary automatically
Text(...) // Uses DesignConstants.text automatically
```

**Theme Variations**: Inherit from DesignConstants and override specific values
```dart
class LightDesignConstants extends DesignConstants {
  static const Color background = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF000000);
  // Inherit other values, override only what changes
}
```

**Custom Widget Components**: Build reusable components in `lib/shared/widgets/`
- Use DesignConstants for specific styling needs
- Example: PrimaryButton, SecondaryButton, CustomCard

## Project Structure

**Domain-Driven Architecture with Bloc**
```
lib/
├── main.dart                    # Application entry point
├── app/                         # App configuration
│   ├── app.dart                 # MaterialApp setup
│   └── routes.dart              # Route definitions
├── core/                        # Shared utilities
│   ├── constants/
│   │   └── design_constants.dart  # Design system constants (colors, fonts, styles)
│   ├── errors/
│   ├── network/
│   └── utils/
├── features/                    # Feature modules
│   ├── auth/
│   │   ├── bloc/                # Bloc, Events, States
│   │   │   ├── auth_bloc.dart
│   │   │   ├── auth_event.dart
│   │   │   └── auth_state.dart
│   │   ├── data/                # Repositories, data sources
│   │   │   ├── repositories/
│   │   │   └── models/
│   │   └── presentation/        # Screens, widgets
│   │       ├── screens/
│   │       └── widgets/
│   └── home/
│       └── ...
└── shared/                      # Shared widgets, themes
    ├── widgets/
    └── themes/
        └── app_theme.dart         # Theme configuration
```

**Why Domain-Driven**
- Clear boundaries between business domains
- Easy to scale and maintain
- Teams can work independently
- Promotes separation of concerns

## State Management with Bloc

**Bloc Patterns**
- One Bloc per feature/screen
- Events describe user actions or system events
- States represent UI state at any point
- Use `Equatable` for Events and States
- Use `sealed` classes for States when appropriate
- Keep Blocs focused - split if handling too many concerns

**Callbacks vs Bloc**
- **Avoid callbacks unless extremely necessary** - use Bloc for state management instead
- Good: Widget dispatches an event to Bloc, Bloc updates state, widget rebuilds
- Bad: Passing callbacks through multiple widget layers for state changes
- Callbacks are acceptable for: simple UI interactions (onTap on a button), form field changes
- For business logic and state changes: ALWAYS use Bloc events

**Bloc Best Practices**
- **Never emit state in constructor** - use `on<Event>` handlers
- **Use `transformEvents`** for debouncing/throttling
- **Close streams** in `close()` method
- **Test Blocs thoroughly** - they contain business logic
- **Use BlocObserver** for logging/analytics

**Layer Separation**
- Screen → Bloc → Repository → Data Source
- Screen handles UI concerns and user interactions
- Bloc handles business logic and state management
- Repository handles data access and caching
- Never skip layers

## Error Handling

**Exception Strategy**
- Create custom exception hierarchy in `core/errors/`
- Blocs catch exceptions and emit error states
- Widgets display user-friendly error messages
- Log errors for debugging

**Logging and Exception Strategy**
- **Bloc layer**: Use logging package to log errors with stack traces
  - Good: `log('Auth failed', error: e, stackTrace: stackTrace)`
  - Log before emitting error state to capture full context
- **Repository/Service layers**: Just throw exceptions with relevant messages
  - Good: `throw NetworkException('Failed to fetch user data')`
  - Focus on clear, descriptive exception messages
- **Layer Separation**: Blocs log + handle, Repositories throw + describe

**Bloc Error Handling**
```dart
on<FetchDataRequested>((event, emit) async {
  emit(DataLoading());
  try {
    final data = await repository.fetchData();
    emit(DataLoaded(data));
  } on NetworkException catch (e) {
    emit(DataError(e.message));
  }
});
```

## Testing

**Test Structure**
- Use `flutter_test` and `bloc_test` packages
- Separate unit, widget, and integration tests
- Fixtures for common setup
- One test file per module

**Test Types**
- **Unit tests**: Blocs, repositories, utilities
- **Widget tests**: Individual widgets and screens
- **Integration tests**: Full user flows
- Test error conditions and edge cases

**Testing Requirements**
- **Zero Test Failures**: All tests must pass - NO EXCEPTIONS
- **Test Coverage**: Aim for 80%+ coverage
- **Test Organization**: Tests mirror the lib/ folder structure in test/
- **Mock Usage**: Proper mocking of repositories and services
- **Continuous Testing**: Run `flutter test` before any commit

**Bloc Testing**
```dart
blocTest<AuthBloc, AuthState>(
  'emits [loading, authenticated] when login succeeds',
  build: () => AuthBloc(authRepository: mockAuthRepo),
  act: (bloc) => bloc.add(LoginRequested(email, password)),
  expect: () => [AuthLoading(), Authenticated(user)],
);
```

## Code Quality

**IMPORTANT: Always run `flutter analyze` after making code changes**
- Run before committing any changes
- Fix ALL warnings and errors
- This ensures code quality and consistency

### Zero Warnings Policy
- **NEVER USE DEPRECATED METHODS**: Always use the latest non-deprecated alternatives
- **Fix All Warnings**: If `flutter analyze` shows ANY warnings, they must be fixed immediately
- **Stay Current**: Use modern Flutter/Dart APIs (e.g., use `.withValues()` instead of `.withOpacity()`)

### Widget Architecture Principles
- **Single Responsibility**: Each widget has one clear purpose
- **No Complex Conditional Rendering**: Replace complex if/else with dedicated widgets
- **Separation of Concerns**: UI separated from business logic (use Bloc)
- **Composition over Inheritance**: Use widget composition for complex UIs
- **NO HARDCODING**: Never hardcode data values, strings, or configurations in widgets

### Production-Ready Standards
- **Comprehensive Testing**: Every feature must have corresponding tests
- **Error Handling**: All widgets/blocs handle edge cases gracefully
- **Null Safety**: Full null safety compliance
- **Performance**: Efficient widget rebuilds, use `const` constructors
- **Maintainability**: Clear naming conventions and documentation

## Dependencies

**Dependency Management**
- **ALWAYS use `flutter pub add <package>`** to add dependencies
- **NEVER manually modify pubspec.yaml** for dependencies
- Use `flutter pub add --dev <package>` for dev dependencies

**Core Dependencies**
- `flutter_bloc` - State management
- `equatable` - Value equality for Events/States
- `get_it` - Service locator/dependency injection
- `dio` - HTTP client

## Security

**Input Validation**
- Always validate user input
- Sanitize data before display
- Use parameterized queries for local databases

**Configuration**
- Environment variables for secrets (use `flutter_dotenv`)
- Never commit API keys or secrets
- HTTPS only for network requests

## Documentation

**Code Documentation**
- Docstrings for all public functions/classes
- Document parameters, return values, exceptions
- Keep documentation updated with code changes

## Code Quality Checklist

- [ ] Follows SOLID principles
- [ ] Uses Bloc for state management
- [ ] Type annotations on all functions
- [ ] Feature-based project structure
- [ ] Repository pattern for data access
- [ ] Bloc for business logic
- [ ] Comprehensive tests (unit, widget, bloc)
- [ ] Proper error handling
- [ ] No hardcoded values
- [ ] `flutter analyze` passes with no warnings
- [ ] All tests pass
- [ ] No secrets in code

**Remember: Code is read more often than written. Prioritize clarity, modularity, and maintainability.**
