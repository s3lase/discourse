import componentTest, {
  setupRenderingTest,
} from "discourse/tests/helpers/component-test";
import {
  discourseModule,
  exists,
  query,
  queryAll,
} from "discourse/tests/helpers/qunit-helpers";
import { MiniReviewable } from "discourse/models/reviewable";
import hbs from "htmlbars-inline-precompile";
import I18n from "I18n";

function getReviewable(overrides = {}) {
  return MiniReviewable.create(
    Object.assign(
      {
        flagger_username: "sayo2",
        id: 17,
        pending: false,
        post_number: 3,
        topic_title: "anything hello world",
        type: "ReviewableFlaggedPost",
      },
      overrides
    )
  );
}

discourseModule(
  "Integration | Component | user-menu | default-reviewable-item",
  function (hooks) {
    setupRenderingTest(hooks);

    const template = hbs`<UserMenu::DefaultReviewableItem @item={{this.item}}/>`;

    componentTest(
      "doesn't push `reviewed` to the classList if the reviewable is pending",
      {
        template,

        beforeEach() {
          this.set("item", getReviewable({ pending: true }));
        },

        async test(assert) {
          assert.ok(!exists("li.reviewed"));
          assert.ok(exists("li"));
        },
      }
    );

    componentTest(
      "pushes `reviewed` to the classList if the reviewable isn't pending",
      {
        template,

        beforeEach() {
          this.set("item", getReviewable({ pending: false }));
        },

        async test(assert) {
          assert.ok(exists("li.reviewed"));
        },
      }
    );

    componentTest("has 2 spans: one for label and one for description", {
      template,

      beforeEach() {
        this.set("item", getReviewable());
      },

      async test(assert) {
        const spans = queryAll("li span");
        assert.strictEqual(spans.length, 2);

        assert.strictEqual(
          spans[0].textContent.trim(),
          "sayo2",
          "the label contains flagger_username"
        );

        assert.strictEqual(
          spans[0].textContent.trim(),
          "sayo2",
          "the label is the flagger_username"
        );
        assert.strictEqual(
          spans[1].textContent.trim(),
          I18n.t("user_menu.reviewable.default_item", {
            reviewable_id: this.item.id,
          }),
          "the description is a generic I18n string"
        );
      },
    });

    componentTest(
      "the item's label is an I18n string if flagger_username is absent",
      {
        template,

        beforeEach() {
          this.set("item", getReviewable({ flagger_username: null }));
        },

        async test(assert) {
          const label = query("li span");
          assert.strictEqual(
            label.textContent.trim(),
            I18n.t("user_menu.reviewable.deleted_user")
          );
        },
      }
    );
  }
);
