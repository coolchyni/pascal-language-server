# PasLS

Pascal language support for Sublime Text's LSP plugin, powered by the [Pascal Language Server](https://github.com/genericptr/pascal-language-server).

### Installing PasLS

1. Clone or download this repository
2. Create a directory named `PasLS` in your Sublime Text `Packages` directory:
   - macOS: `~/Library/Application Support/Sublime Text/Packages/PasLS`
   - Linux: `~/.config/sublime-text/Packages/PasLS`
   - Windows: `%APPDATA%\Sublime Text\Packages\PasLS`
3. Copy all files from this repository into that directory
4. Restart Sublime Text
5. The Pascal Language Server binary will be automatically downloaded from GitHub releases

### Binary Installation

By default, PasLS will automatically download and manage the `pasls` binary from [GitHub releases](https://github.com/genericptr/pascal-language-server/releases). The binary is stored in `$CACHE/Package Storage/PasLS`.

**Automatic Installation (Recommended):**
- Set `"manageBinary": true` in settings (default)
- The plugin will download the appropriate binary for your platform
- Updates are checked and applied automatically

**Manual Installation:**
- Set `"manageBinary": false` in settings
- Build pasls yourself following the [build instructions](https://github.com/genericptr/pascal-language-server)
- Configure the full path to your binary in the `command` setting

**Binary Naming Convention:**

For automatic installation to work, GitHub releases should include platform-specific binaries:
- macOS Intel: `pasls-darwin-x86_64`
- macOS Apple Silicon: `pasls-darwin-aarch64`
- Linux: `pasls-linux-x86_64`
- Windows: `pasls-win64-x86_64.exe`

The plugin will automatically detect your platform and download the appropriate binary. If no platform-specific binary is found, you must build pasls manually and use manual installation mode.

## Configuration

You must set up the required environment variables for the Pascal compiler. The binary path is configured automatically unless you're using manual installation mode.

### Global Configuration

1. Open Sublime Text preferences: `Preferences > Package Settings > PasLS > Settings`
2. Configure your environment variables in the user settings:

**Automatic Binary Management (Default):**
```json
{
  "env": {
    "FPCDIR": "/usr/local/share/fpcsrc",
    "FPCTARGET": "darwin",
    "FPCTARGETCPU": "x86_64",
    "LAZARUSDIR": "/usr/share/lazarus",
    "PP": "/usr/local/lib/fpc/3.2.2/ppcx64"
  }
}
```

**Manual Binary Management:**
```json
{
  "manageBinary": false,
  "command": ["/path/to/pascal-language-server/pasls"],
  "env": {
    "FPCDIR": "/usr/local/share/fpcsrc",
    "FPCTARGET": "darwin",
    "FPCTARGETCPU": "x86_64",
    "LAZARUSDIR": "/usr/share/lazarus",
    "PP": "/usr/local/lib/fpc/3.2.2/ppcx64"
  }
}
```

You can also use the Command Palette: `Preferences: PasLS Settings`

**Note:** Do not configure PasLS in `Preferences > Package Settings > LSP > Settings` under the `clients` section. That section is only for language servers that don't have their own package.

### Project-Specific Configuration

You can override settings per project by adding LSP settings to your `.sublime-project` file:

```json
{
  "folders": [
    {
      "path": "."
    }
  ],
  "settings": {
    "LSP": {
      "PasLS": {
        "enabled": true,
        "command": ["/path/to/pasls"],
        "env": {
          "FPCDIR": "/usr/local/share/fpcsrc",
          "FPCTARGET": "linux",
          "FPCTARGETCPU": "x86_64"
        },
        "initializationOptions": {
          "fpcOptions": [
            "-Fu/path/to/your/units",
            "-Fi/path/to/your/includes",
            "-dDEBUG"
          ],
          "symbolDatabase": "$(tmpdir)/myproject-symbols.db"
        }
      }
    }
  }
}
```

## Links

- [Pascal Language Server](https://github.com/genericptr/pascal-language-server)
- [LSP for Sublime Text](https://github.com/sublimelsp/LSP)
- [Language Server Protocol](https://microsoft.github.io/language-server-protocol/)
