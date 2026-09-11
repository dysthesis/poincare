import { always, Cell, next } from "@antithesishq/bombadil";
import { extract, weighted } from "@antithesishq/bombadil/terminal";

const escapeRegex = (text: string) =>
  text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

const literal = (text: string) => ({
  TypeText: {
    Regexp: escapeRegex(text),
  },
});

export const linterActions = weighted([
  [
    4,
    literal(
      ":edit /tmp/poincare-bombadil/linters/project/src/main.rs\r",
    ),
  ],
  [
    4,
    literal(
      ":edit /tmp/poincare-bombadil/linters/project/src/lib.rs\r",
    ),
  ],
  [2, literal(":call append(line('$'), '// bombadil')\r")],
  [4, literal(":write\r")],
  [2, literal(":undo\r")],
  [2, literal(":edit!\r")],
]);

const screen: Cell<string> = extract((state) => {
  const { rows } = state.grid.size;

  let text = "";

  for (let row = 0; row < rows; row++) {
    text += state.grid.rowText(row) + "\n";
  }

  return text;
});

export const noNvimErrors = always(
  next(() => {
    const text = screen.current ?? "";

    return !(
      text.includes("Error detected while processing") ||
      text.includes("Error in BufReadPost") ||
      text.includes("Error in BufWritePost") ||
      text.includes("E5108:") ||
      text.includes("stack traceback:") ||
      text.includes("bad argument")
    );
  }),
);
