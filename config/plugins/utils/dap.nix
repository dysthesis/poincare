{pkgs, ...}: {
  plugins.dap = {
    enable = true;
    extensions = {
      dap-ui.enable = true;
      dap-virtual-text.enable = true;
    };
    adapters.executables = {
      codelldb = {
        command = "${pkgs.vscode-extensions.vadimcn.vscode-lldb}/bin/codelldb";
        args = ["--interpreter=vscode"];
      };
    };
  };
}
