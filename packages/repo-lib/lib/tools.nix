{
  lib,
}:
let
  normalizeStrictTool =
    pkgs: tool:
    let
      version = {
        args = [ "--version" ];
        match = null;
        regex = null;
        group = 0;
        line = 1;
      }
      // (tool.version or { });
      banner = {
        color = "YELLOW";
        icon = null;
        iconColor = null;
      }
      // (tool.banner or { });
      executable =
        if tool ? command && tool.command != null then
          tool.command
        else if tool ? exe && tool.exe != null then
          "${lib.getExe' tool.package tool.exe}"
        else
          "${lib.getExe tool.package}";
    in
    if !(tool ? command && tool.command != null) && !(tool ? package) then
      throw "repo-lib: tool '${tool.name or "<unnamed>"}' is missing 'package' or 'command'"
    else
      {
        kind = "strict";
        inherit executable version banner;
        name = tool.name;
        package = tool.package or null;
        required = tool.required or true;
      };
in
{
  inherit normalizeStrictTool;

  tools = rec {
    fromPackage =
      {
        name,
        package,
        exe ? null,
        version ? { },
        banner ? { },
        required ? true,
      }:
      {
        inherit
          name
          package
          exe
          version
          banner
          required
          ;
      };

    fromCommand =
      {
        name,
        command,
        version ? { },
        banner ? { },
        required ? true,
      }:
      {
        inherit
          name
          command
          version
          banner
          required
          ;
      };

    simple =
      name: package: args:
      fromPackage {
        inherit name package;
        version.args = args;
      };
  };
}
