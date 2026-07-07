> ⚠️ **Unofficial Builds** - These are **NOT** official TeXstudio builds. This is an independent project providing custom builds with Qt6 and Poppler for modern Linux distributions. The official TeXstudio project does not endorse or support these builds.
> 
> For official builds, visit: https://www.texstudio.org/

---

# TeXstudio Builds

Custom builds of [TeXstudio](https://www.texstudio.org/) with **Qt6** and **Poppler** for modern Linux distributions.

## Features

- ✅ Built with **Qt6** (modern Qt framework)
- ✅ **Poppler** PDF viewer (better rendering than Poppler-Qt5)
- ✅ Optimized for Debian/Ubuntu-based distributions
- ✅ Automatic updates via APT repository
- ✅ All dependencies included

## 🚀 Quick Install (Recommended)

The easiest way to install TeXstudio and keep it updated is via our APT repository. This method will **automatically install all required dependencies** (Qt6, Poppler, Hunspell, etc.).

### 1. Add the repository

```bash
echo "deb [trusted=yes] https://mlmateos.github.io/texstudio-builds/ pool/" |   sudo tee /etc/apt/sources.list.d/texstudio.list
```

### 2. Update package list

```bash
sudo apt update
```

### 3. Install TeXstudio

```bash
sudo apt install texstudio
```

**Note:** This will automatically download and install all required dependencies, including:
- Qt6 libraries
- Poppler-Qt6 (PDF viewer)
- Hunspell (spell checking)
- QuaZip
- And other required libraries

### 4. Verify installation

```bash
texstudio --version
# Should show: TeXstudio 4.9.5 (4.9.5)
```

### Updating

When a new version is released, simply run:

```bash
sudo apt update
sudo apt upgrade texstudio
```

---

## 📦 Alternative: Manual Installation

If you prefer to download the `.deb` package directly:

1. Go to [Releases](https://github.com/mlmateos/texstudio-builds/releases)
2. Download the latest `texstudio-*-qt6-amd64.deb`
3. Install with:

```bash
sudo apt install ./texstudio-*-qt6-amd64.deb
```

Dependencies will be automatically resolved and installed.

---

## 🐧 AppImage (Portable)

For a portable version that works on any Linux distribution:

1. Download the latest `texstudio-*-qt6-x86_64.AppImage` from [Releases](https://github.com/mlmateos/texstudio-builds/releases)
2. Make it executable:

```bash
chmod +x texstudio-*.AppImage
./texstudio-*.AppImage
```

---

## 🔨 Build from Source

If you want to compile TeXstudio yourself, this repository provides automated build scripts.

### Prerequisites

```bash
# Clone the repository
git clone https://github.com/mlmateos/texstudio-builds.git
cd texstudio-builds/scripts
```

### Available Scripts

- `install-texstudio-deps.sh` - Install build dependencies
- `build-texstudio-appimage.sh` - Build AppImage
- `build-texstudio-deb.sh` - Build .deb package

### Quick Build

```bash
# Install dependencies
./install-texstudio-deps.sh

# Build .deb package
./build-texstudio-deb.sh --clean --poppler --sign

# Or build AppImage
./build-texstudio-appimage.sh --clean --poppler --sign
```

### Advanced Usage

```bash
# Build specific version
./build-texstudio-deb.sh --branch 4.9.5 --clean --poppler --sign

# Publish to GitHub Releases
./build-texstudio-deb.sh --clean --poppler --sign --publish
```

See `--help` for all available options.

---

## 📋 Current Version

- **Stable:** 4.9.5 (Qt6 + Poppler)
- **Pre-release:** 4.9.6-alpha3 (testing new features)

## 🛠️ System Requirements

- **OS:** Debian 12+, Ubuntu 22.04+, or compatible
- **Architecture:** x86_64 (amd64)
- **Disk Space:** ~400 MB (including dependencies)
- **RAM:** 2 GB minimum, 4 GB recommended

## 📄 License

This project is licensed under the [MIT License](LICENSE).

TeXstudio itself is licensed under [GPL-2.0+](https://github.com/texstudio-org/texstudio/blob/master/LICENSE).

## 🤝 Contributing

Issues and pull requests are welcome!

## 📞 Support

- **GitHub Issues:** [Report a bug](https://github.com/mlmateos/texstudio-builds/issues)
- **Documentation:** [TeXstudio Manual](https://texstudio.github.io/manual.html)

---

**Happy TeXing~/texstudio-builds* 🎓
