from LSP.plugin import AbstractPlugin
from LSP.plugin import register_plugin
from LSP.plugin import unregister_plugin
import gzip
import io
import json
import os
import shutil
import stat
import sublime
import urllib.request


# GitHub repository information
GITHUB_REPO = "genericptr/pascal-language-server"
GITHUB_API_URL = "https://api.github.com/repos/{}/releases/latest".format(GITHUB_REPO)


def plugin_loaded():
    """Called when the plugin is loaded."""
    register_plugin(PascalLanguageServer)


def plugin_unloaded():
    """Called when the plugin is unloaded."""
    unregister_plugin(PascalLanguageServer)


class PascalLanguageServer(AbstractPlugin):
    """Pascal Language Server plugin for Sublime Text."""

    @classmethod
    def name(cls):
        """Return the plugin name."""
        return "PasLS"

    @classmethod
    def basedir(cls):
        """Return the base directory for storing the language server."""
        return os.path.join(sublime.cache_path(), "Package Storage", cls.name())

    @classmethod
    def server_path(cls):
        """Return the path to the language server binary."""
        binary_name = "pasls.exe" if sublime.platform() == "windows" else "pasls"
        return os.path.join(cls.basedir(), binary_name)

    @classmethod
    def version_file(cls):
        """Return the path to the version file."""
        return os.path.join(cls.basedir(), "VERSION")

    @classmethod
    def get_installed_version(cls):
        """Get the currently installed version."""
        try:
            with open(cls.version_file(), "r") as f:
                return f.read().strip()
        except FileNotFoundError:
            return None

    @classmethod
    def set_installed_version(cls, version):
        """Save the installed version."""
        os.makedirs(cls.basedir(), exist_ok=True)
        with open(cls.version_file(), "w") as f:
            f.write(version)

    @classmethod
    def configuration(cls):
        """Return the plugin configuration."""
        base_file = "{}.sublime-settings".format(cls.name())
        settings = sublime.load_settings(base_file)
        resource_path = "Packages/{}/{}".format(cls.name(), base_file)
        return settings, resource_path

    @classmethod
    def additional_variables(cls):
        """Return additional variables for the plugin."""
        return {
            "server_path": cls.server_path(),
        }

    @classmethod
    def needs_update_or_installation(cls):
        """Check if the language server needs to be installed or updated."""
        settings, _ = cls.configuration()
        if not settings.get("manageBinary", True):
            return False

        # Check if binary exists
        if not os.path.exists(cls.server_path()):
            return True

        # Check if we can get the latest version from GitHub
        try:
            with urllib.request.urlopen(GITHUB_API_URL, timeout=10) as response:
                data = json.loads(response.read().decode("utf-8"))
                latest_tag = data.get("tag_name", "")
                installed_version = cls.get_installed_version()
                return latest_tag != installed_version
        except urllib.error.HTTPError as e:
            print("{}: Failed to check for updates from {}: HTTP {} {}".format(cls.name(), GITHUB_API_URL, e.code, e.reason))
            return False
        except Exception as e:
            print("{}: Failed to check for updates: {}".format(cls.name(), e))
            return False

    @classmethod
    def install_or_update(cls):
        """Install or update the language server."""
        try:
            # Get release information
            print("{}: Fetching release information from {}".format(cls.name(), GITHUB_API_URL))
            with urllib.request.urlopen(GITHUB_API_URL, timeout=30) as response:
                data = json.loads(response.read().decode("utf-8"))

            tag_name = data.get("tag_name", "")
            if not tag_name:
                raise Exception("No tag_name in release data")

            # Determine platform and architecture
            platform = sublime.platform()
            arch = sublime.arch()

            # Map Sublime platform/arch to release naming conventions
            platform_map = {
                "osx": "darwin",
                "linux": "linux",
                "windows": "win64"
            }

            arch_map = {
                "x64": "x86_64",
                "x32": "i386",
                "arm64": "aarch64"
            }

            release_platform = platform_map.get(platform, platform)
            release_arch = arch_map.get(arch, arch)

            # Find matching asset
            # Look for assets with platform/arch in the name or tag
            binary_name = "pasls.exe" if platform == "windows" else "pasls"
            asset_url = None

            # First pass: Look for exact platform-arch match
            for asset in data.get("assets", []):
                asset_name = asset.get("name", "").lower()
                # Check for platform-arch combination (e.g., pasls-darwin-aarch64)
                if release_platform in asset_name and release_arch in asset_name:
                    asset_url = asset.get("browser_download_url")
                    break

            # Second pass: Look for platform match only
            if not asset_url:
                for asset in data.get("assets", []):
                    asset_name = asset.get("name", "").lower()
                    # Check if asset matches platform (e.g., pasls-darwin)
                    if asset_name.startswith("pasls-{}".format(release_platform)):
                        asset_url = asset.get("browser_download_url")
                        break

            # Third pass: Try the generic binary name
            if not asset_url:
                for asset in data.get("assets", []):
                    if asset.get("name") == binary_name:
                        asset_url = asset.get("browser_download_url")
                        break

            # If still no asset, construct URL from tag
            if not asset_url:
                # For releases that embed platform in tag name
                if release_platform in tag_name or release_arch in tag_name:
                    asset_url = "https://github.com/{}/releases/download/{}/{}".format(GITHUB_REPO, tag_name, binary_name)
                else:
                    raise Exception(
                        "No suitable binary found for {}-{}. "
                        "Please install pasls manually and set manageBinary to false.".format(release_platform, release_arch)
                    )

            print("{}: Downloading binary from {}".format(cls.name(), asset_url))

            # Download the binary
            os.makedirs(cls.basedir(), exist_ok=True)
            temp_path = cls.server_path() + ".tmp"

            try:
                with urllib.request.urlopen(asset_url, timeout=300) as response:
                    data_bytes = response.read()
            except urllib.error.HTTPError as e:
                raise Exception("Failed to download binary from {}: HTTP {} {}".format(asset_url, e.code, e.reason))

            # Check if it's gzipped
            if asset_url.endswith(".gz"):
                with gzip.open(io.BytesIO(data_bytes), "rb") as gz_file:
                    data_bytes = gz_file.read()

            # Write the binary
            with open(temp_path, "wb") as f:
                f.write(data_bytes)

            # Make it executable (Unix-like systems)
            if platform != "windows":
                st = os.stat(temp_path)
                os.chmod(temp_path, st.st_mode | stat.S_IEXEC)

            # Move to final location
            shutil.move(temp_path, cls.server_path())

            # Save version
            cls.set_installed_version(tag_name)

            print("{}: Successfully installed version {}".format(cls.name(), tag_name))

        except urllib.error.HTTPError as e:
            print("{}: Installation failed: HTTP {} {} - {}".format(cls.name(), e.code, e.reason, e.url if hasattr(e, 'url') else ''))
            raise Exception("Failed to download latest {}".format(cls.name()))
        except Exception as e:
            print("{}: Installation failed: {}".format(cls.name(), e))
            raise Exception("Failed to download latest {}".format(cls.name()))
