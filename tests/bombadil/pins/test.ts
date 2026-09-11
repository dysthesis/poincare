import { weighted } from "@antithesishq/bombadil/terminal";

const literal = (text: string) => ({
  TypeText: {
    Regexp: text,
  },
});

export const poincareActions = weighted([
  [2, literal(":edit /tmp/poincare-bombadil/a/a\\.rs\r")],
  [2, literal(":edit /tmp/poincare-bombadil/b/b\\.rs\r")],
  [3, literal(" h")],
  [5, literal(":PoincareCheck\r")],
]);
