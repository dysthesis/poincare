{
  plugins.ollama = {
    enable = true;
    model = "deepseek-coder";
    action = "display";

    extraOptions = {
      prompts = {
        code_instruct = {
          action = "display";
          model = "codellama:7b-instruct";
          input_label = "Code Instruct: codellama > ";
          prompt = ''
            You are an expert programmer that writes simple, concise code and explanations.
            Write $ftype code to do the following:
            $input
          '';
        };

        # TODO: Figure out how to deal with suffix. Parse pre-input before/after current line/selection?
        code_infill = {
          action = "insert";
          model = "codellama:7b-code";
          input_label = "Code Infill: codellama > ";
          prompt = "<PRE> $buf <SUF> {suffix} <MID>";
        };

        code_review = {
          action = "display";
          model = "codellama";
          input_label = "Code Review: codellama > ";
          prompt = ''
            Where is the bug in this $ftype code?:
            $sel
          '';
        };

        # Code Completion Models:
        # - stable-code: https://ollama.com/library/stable-code (python, C++, JS, Java) - 3B, fill-in-the-middle
        # - CodeLLama: https://ollama.com/library/codellama (Rust, PHP, JS) - 7B
        code_complete = {
          prompt = "Complete the following code.";
          model = "codellama"; # "codellama:7b-instruct" "codellama:7b-code" "codellama:7b-python";
          input_label = "> "; # Label to use for the input prompt.
          action = {
            display =
              true; # Stream and display the response in a floating window.
            replace = false; # Replace the current selection with the response.
            insert = true; # Insert the response at the current cursor line
            display_replace =
              false; # Stream and display the response in a floating window, then replace the current selection with the response.
            display_insert =
              false; # Stream and display the response in a floating window, then insert the response at the current cursor line.
          };
        };
      };
    };
  };
}
