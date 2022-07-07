import { emojiUnescape } from "discourse/lib/text";
import { escapeExpression } from "discourse/lib/utilities";
import { htmlSafe } from "@ember/template";
import { helper } from "@ember/component/helper";

function emoji(code) {
  const escaped = escapeExpression(`:${code}:`);
  return htmlSafe(emojiUnescape(escaped));
}

export default helper(emoji);
