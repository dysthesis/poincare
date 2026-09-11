import { always, Cell, next } from "@antithesishq/bombadil";
import { extract, weighted } from "@antithesishq/bombadil/terminal";

const literal = (text: string) => ({
  TypeText: {
    Regexp: text,
  },
});

export const poincareActions = weighted([
  [2, literal(":edit /tmp/poincare-bombadil/a/a\r")],
  [2, literal(":edit /tmp/poincare-bombadil/b/b\r")],
  [3, literal(" h")],
  [5, literal(":PoincareCheck\r")],
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
      text.includes("E5108:") ||
      text.includes("stack traceback:") ||
      text.includes("bad argument")
    );
  }),
);
