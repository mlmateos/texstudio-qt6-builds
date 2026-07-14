⚠️ **Unofficial Builds** — These are NOT official TeXstudio builds. This is an independent project providing custom builds with Qt6 and Poppler for modern Linux distributions. The official TeXstudio project does not endorse or support these builds.

For official builds, visit: https://www.texstudio.org/

# TeXstudio Qt6 Builds

[![GitHub release](https://img.shields.io/github/v/release/mlmateos/texstudio-qt6-builds?include_prereleases&label=latest)](https://github.com/mlmateos/texstudio-qt6-builds/releases)
[![License](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](https://github.com/mlmateos/texstudio-qt6-builds/blob/master/LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20x86__64-lightgrey)](https://github.com/mlmateos/texstudio-qt6-builds)

Custom builds of [TeXstudio](https://www.texstudio.org/) with Qt6 and Poppler for modern Linux distributions.

## ✨ Features

- 🎨 **Qt6 framework** — Modern UI/UX with improved performance
- 📖 **Poppler-Qt6** — Native PDF viewer with better rendering than Qt5
-  **Auto-updates** — Integrated update checker pointing to this repository
- 🔐 **GPG-signed packages** — Security verification for all releases
- 📦 **Two distribution methods:**
  - `.deb` packages for Debian/Ubuntu-based distributions
  - `AppImage` for any Linux distribution (portable, no installation required)
- 🛠️ **Automated build scripts** — Compile your own version easily

## 🚀 Quick Install (Recommended)

The easiest way to install TeXstudio and keep it automatically updated is via our APT repository.

### Step 1: Choose Your Branch

Choose one of the following options:

**🟢 Stable** (recommended for most users) — Only stable releases:
```bash
echo "deb [trusted=yes] https://mlmateos.github.io/texstudio-qt6-builds/ stable main" | \
  sudo tee /etc/apt/sources.list.d/texstudio.list
```

**🟡 Alpha** — Development versions (alpha, beta, rc) + stable:
```bash
echo "deb [trusted=yes] https://mlmateos.github.io/texstudio-qt6-builds/ alpha main" | \
  sudo tee /etc/apt/sources.list.d/texstudio.list
```

💡 **Tip:** You can switch between branches at any time by running the corresponding command again.

### Step 2: Install TeXstudio

```bash
sudo apt update
sudo apt install texstudio
```

All required dependencies (Qt6, Poppler-Qt6, Hunspell, QuaZip, etc.) will be automatically downloaded and installed.

### Step 3: Verify Installation

```bash
texstudio --version
```

### Updating

When a new version is released for your chosen branch:

```bash
sudo apt update
sudo apt upgrade texstudio
```

### Uninstalling

```bash
sudo apt remove texstudio
sudo rm /etc/apt/sources.list.d/texstudio.list
```

## 🔔 Get Release Notifications

Want to be notified when a new version is released? Here are two easy options:

### Option 1: GitHub Notifications (Recommended)

1. Click the **"Watch"** button at the top right of this repository
2. Select **"Custom"**
3. Check only **"Releases"**
4. Click **"Apply"**

💡 **Note:** Make sure you have email notifications enabled in your GitHub account settings (Settings > Notifications > Email).

### Option 2: Email via RSS Feed

Use this RSS feed link: `https://github.com/mlmateos/texstudio-qt6-builds/releases.atom`

Paste it into a free service like:
- **[Blogtrottr](https://blogtrottr.com/)** — Get instant or daily digest emails
- **[Feedrabbit](https://feedrabbit.com/)** — Simple RSS to email service

## 📦 Alternative Installation Methods

### Method 2: Direct `.deb` Download

If you prefer not to use the APT repository:

1. Go to [Releases](https://github.com/mlmateos/texstudio-qt6-builds/releases)
2. Download the latest `texstudio-*-qt6-amd64.deb`
3. Install with:
   ```bash
   sudo apt install ./texstudio-*-qt6-amd64.deb
   ```

### Method 3: AppImage (Portable)

For a portable version that works on any Linux distribution (no installation required):

1. Download the latest `texstudio-*-qt6-x86_64.AppImage` from [Releases](https://github.com/mlmateos/texstudio-qt6-builds/releases)
2. Make it executable and run:
   ```bash
   chmod +x texstudio-*.AppImage
   ./texstudio-*.AppImage
   ```

💡 **Tip:** You can place the AppImage anywhere in your system, even on a USB drive.

## 🔨 Build from Source

This repository provides automated build scripts for both `.deb` packages and `AppImage`.

### Step 1: Install Dependencies

Run the included dependency installer script:

```bash
cd ~/texstudio-qt6-builds/scripts
./install-deps.sh
```

This script will automatically install:
- Build tools (cmake, git, make, etc.)
- Qt6 libraries
- Poppler-Qt6
- Hunspell, QuaZip, and other TeXstudio dependencies
- AppImage tools (patchelf, appimagetool)
- GitHub CLI (for publishing)
- GPG (for signing)

### Step 2: Clone the Repository

```bash
git clone https://github.com/mlmateos/texstudio-qt6-builds.git
cd texstudio-qt6-builds/scripts
```

### Step 3: Build

```bash
# Build .deb package
./build-texstudio-deb.sh --clean --poppler --sign

# Or build AppImage
./build-texstudio-appimage.sh --clean --poppler --sign
```

## Available Scripts

| Script | Description |
|--------|-------------|
| `install-deps.sh` | Install all build dependencies |
| `build-texstudio-deb.sh` | Build `.deb` package with Qt6 + Poppler |
| `build-texstudio-appimage.sh` | Build portable `AppImage` with Qt6 + Poppler |

## Complete Options Reference

Both build scripts support the following options:

| Option | Description |
|--------|-------------|
| `--clean` | Clean build directory before starting |
| `--branch NAME` | Branch or tag to compile (e.g., `4.9.5`, `4.9.6beta3`, `master`) |
| `--jobs N` | Number of parallel compilation threads (auto-detected by default) |
| `--poppler` | Enable Poppler-Qt6 PDF viewer (highly recommended) |
| `--sign` | Sign the resulting package with GPG |
| `--publish` | Publish the result to GitHub Releases |
| `--gpg-key ID` | Use a specific GPG key for signing |
| `--revision N` | Debian package revision (default: `1`) — `.deb` only |
| `--help` | Show all available options |

## Example Workflows

```bash
# Install all dependencies first
./install-deps.sh

# Build and publish a specific version
./build-texstudio-deb.sh --branch 4.9.6beta3 --clean --poppler --sign --publish

# Quick rebuild (keeping source code)
./build-texstudio-deb.sh --clean --poppler --sign

# Build using 8 parallel jobs
./build-texstudio-deb.sh --jobs 8 --clean --poppler --sign

# Build from master branch (latest code)
./build-texstudio-deb.sh --branch master --clean --poppler --sign
```

## What the Scripts Do (Step by Step)

1. 🔍 Verify dependencies (and install missing ones automatically)
2.  Clone/update TeXstudio source from upstream
3. 🏷️ Detect version from git tags or specified branch
4. 🛠️ Apply custom patches:
   - Redirect update checker URLs to this repository
   - Add custom credits to the About dialog
   - Mention AI assistance in the About dialog
5. 🔨 Compile TeXstudio with Qt6 and Poppler support
6. 📦 Package the result (`.deb` or `AppImage`)
7. 🔐 Sign with GPG (if `--sign`)
8.  Publish to GitHub Releases (if `--publish`)
9. 🗄️ Update APT repository with proper branch classification (`.deb` only)

##  Current Versions

| Type | Version | Branch |
|------|---------|--------|
|  Development | 4.9.6-beta3 | alpha |
| 🟢 Stable | 4.9.5 | stable, alpha |

## ️ System Requirements

| Component | Requirement |
|-----------|-------------|
| OS | Debian 12+, Devuan 5+, Ubuntu 22.04+, or compatible |
| Architecture | x86_64 (amd64) |
| Disk Space | ~400 MB (including dependencies) |
| RAM | 2 GB minimum, 4 GB recommended |
| glibc | ≥ 2.34 (required for Qt6) |

##  Security

All packages are signed with GPG. You can verify the signatures:

```bash
# Import the GPG key
gpg --keyserver keyserver.ubuntu.com --recv-keys 783C12B9E7463154

# Verify .deb signature
gpg --verify texstudio-*.deb.asc texstudio-*.deb

# Verify AppImage signature
gpg --verify texstudio-*.AppImage.asc texstudio-*.AppImage
```

## 🤝 Contributing

Contributions are welcome! Feel free to:

- 🐛 [Report bugs](https://github.com/mlmateos/texstudio-qt6-builds/issues)
- 💡 [Suggest features](https://github.com/mlmateos/texstudio-qt6-builds/issues)
- 🔧 [Submit pull requests](https://github.com/mlmateos/texstudio-qt6-builds/pulls)

## 📚 Resources

- [TeXstudio Official Site](https://www.texstudio.org/)
- [TeXstudio Manual](https://texstudio-org.github.io/)
- [TeXstudio Source Code](https://github.com/texstudio-org/texstudio)

## 📄 License

This project (build scripts and infrastructure) is licensed under the **MIT License**.

TeXstudio itself is licensed under **GPL-3.0+**.

## 🤖 Acknowledgments

This project was developed with the assistance of [Qwen](https://qwenlm.github.io/), a large language model by Alibaba Group.

Special thanks to the original [TeXstudio](https://github.com/texstudio-org/texstudio) developers: Benito van der Zander, Jan Sundermeyer, Daniel Braun, Tim Hoffmann, and all contributors.

---

<p align="center">
<i>Happy TeXing!</i> 🎓
</p>
```

