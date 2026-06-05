# SysMonitor _(sysmonitor)_

A native macOS system resource widget with menu bar integration and a beautiful glassmorphic UI.

SysMonitor provides an elegant, unobtrusive way to track critical macOS system metrics. It combines a persistent menu bar item for glanceable CPU and RAM usage with a highly detailed, translucent widget window for per-core stats, disk I/O, network throughput, and memory breakdown.

## Features

- **Menu Bar Integration:** Live, compact system stats right in your macOS menu bar.
- **Glassmorphic Widget:** A beautifully designed translucent window that pops down directly from the menu bar.
- **Low Overhead:** Self-regulates its polling interval when hidden to minimize CPU footprint.
- **Smart Alerts:** Native macOS notifications when metrics exceed safe thresholds.

## Install

To install and build SysMonitor from source, you need Xcode installed on your Mac (macOS 13 or later).

```sh
git clone https://github.com/fanioz/sysmonitor.git
cd sysmonitor
xcodebuild -scheme sysmonitor -configuration Release build
open build/Release/sysmonitor.app
```

## Usage

Once launched, SysMonitor will appear in your menu bar. 

```sh
# The app runs entirely in the macOS menu bar
# Left-click the menu bar item to toggle the detailed widget window
# Right-click the menu bar item to access Preferences, set Launch at Login, or Quit
```

## Contributing

Feel free to open an issue or submit a PR. Bug reports and feature requests are welcome.

## License

[MIT](LICENSE) (c) 2026 fanioz
