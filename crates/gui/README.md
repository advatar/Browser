# Decentralized Browser

A privacy-focused, decentralized web browser built with Tauri and Rust.

## Features

- 🌐 Built-in WebView for web browsing
- 🔒 Privacy-focused design
- ⚡ Fast and lightweight
- 🛠️ Developer tools support
- 🔄 Back/Forward navigation
- 🔍 Address bar with URL validation
- 📁 File menu with common browser actions
- ✂️ Edit menu with copy/paste support
- 🔍 View menu with zoom controls

## Getting Started

### Prerequisites

- [Rust](https://www.rust-lang.org/tools/install) (latest stable)
- [Node.js](https://nodejs.org/) (v16 or later)
- [pnpm](https://pnpm.io/) (package manager)

### Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd Browser
   ```

2. Install dependencies:
   ```bash
   pnpm install
   ```

3. Build the project:
   ```bash
   cargo build
   ```

### Running the Application

```bash
cargo run
```

For development with hot-reloading:

```bash
cargo tauri dev
```

## Project Structure

- `src/` - Main application source code
  - `main.rs` - Application entry point and Tauri setup
  - `index.html` - Main browser UI
- `tauri.conf.json` - Tauri configuration
- `Cargo.toml` - Rust dependencies and package configuration

## Development

### Building for Production

```bash
cargo tauri build
```

### Running Tests

```bash
cargo test
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
