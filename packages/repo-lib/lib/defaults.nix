{ }:
{
  supportedSystems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];

  defaultReleaseChannels = [
    "alpha"
    "beta"
    "rc"
    "internal"
  ];

  defaultShellBanner = {
    style = "simple";
    icon = "🚀";
    title = "Dev shell ready";
    titleColor = "GREEN";
    subtitle = "";
    subtitleColor = "GRAY";
    borderColor = "BLUE";
  };
}
