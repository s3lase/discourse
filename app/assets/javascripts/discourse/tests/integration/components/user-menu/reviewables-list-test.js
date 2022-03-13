import componentTest, {
  setupRenderingTest,
} from "discourse/tests/helpers/component-test";
import {
  discourseModule,
  query,
  queryAll,
} from "discourse/tests/helpers/qunit-helpers";
import hbs from "htmlbars-inline-precompile";
import I18n from "I18n";

discourseModule(
  "Integration | Component | user-menu | reviewables-list",
  function (hooks) {
    setupRenderingTest(hooks);

    const template = hbs`<UserMenu::ReviewablesList/>`;

    componentTest("has a 'show all' link", {
      template,

      async test(assert) {
        const showAll = query(".panel-body-bottom a.show-all");
        assert.ok(
          showAll.href.endsWith("/review"),
          "links to the /review page"
        );
        assert.strictEqual(
          showAll.title,
          I18n.t("user_menu.reviewable.view_all"),
          "the 'show all' link has a title"
        );
      },
    });

    componentTest("renders a list of reviewables", {
      template,

      async test(assert) {
        const reviewables = queryAll("ul li");
        assert.strictEqual(reviewables.length, 8);
      },
    });
  }
);
