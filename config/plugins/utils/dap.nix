{pkgs, ...}: {
  plugins.dap = {
    adapters.executables = {
      codelldb = {
        command = "${pkgs.vscode-extensions.vadimcn.vscode-lldb}/bin/codelldb";
        args = ["--interpreter=vscode"];
      };
    };
  };
}
