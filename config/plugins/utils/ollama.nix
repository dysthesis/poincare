{
  plugins.ollama = {
    enable = true;
    model = "deepseek-coder";

    /*
    * The prompt to send to the LLM.
    * Can contain special tokens that are substituted with context before sending.
    */
    prompt = "$input";
  };
}
