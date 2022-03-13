import componentTest, {
  setupRenderingTest,
} from "discourse/tests/helpers/component-test";
import {
  discourseModule,
  exists,
  query,
  queryAll,
} from "discourse/tests/helpers/qunit-helpers";
import { settled } from "@ember/test-helpers";
import { deepMerge } from "discourse-common/lib/object";
import { withPluginApi } from "discourse/lib/plugin-api";
import { NOTIFICATION_TYPES } from "discourse/tests/fixtures/concerns/notification-types";
import Notification from "discourse/models/notification";
import hbs from "htmlbars-inline-precompile";
import I18n from "I18n";

function getNotification(overrides = {}) {
  return Notification.create(
    deepMerge(
      {
        id: 11,
        user_id: 1,
        notification_type: NOTIFICATION_TYPES.mentioned,
        read: false,
        high_priority: false,
        created_at: "2022-07-01T06:00:32.173Z",
        post_number: 113,
        topic_id: 449,
        fancy_title: "This is fancy title &lt;a&gt;!",
        slug: "this-is-fancy-title",
        data: {
          topic_title: "this is title before it becomes fancy <a>!",
          display_username: "osama",
          original_post_id: 1,
          original_post_type: 1,
          original_username: "velesin",
        },
      },
      overrides
    )
  );
}

discourseModule(
  "Integration | Component | user-menu | notification-item",
  function (hooks) {
    setupRenderingTest(hooks);

    const template = hbs`<UserMenu::NotificationItem @item={{this.notification}}/>`;

    componentTest(
      "pushes `read` to the classList if the notification is read",
      {
        template,

        beforeEach() {
          this.set("notification", getNotification());
          this.notification.read = false;
        },

        async test(assert) {
          assert.ok(!exists("li.read"));
          assert.ok(exists("li"));

          this.notification.read = true;
          await settled();

          assert.ok(
            exists("li.read"),
            "the item re-renders when the read property is updated"
          );
        },
      }
    );

    componentTest("pushes the notification type name to the classList", {
      template,

      beforeEach() {
        this.set("notification", getNotification());
      },

      async test(assert) {
        let item = query("li");
        assert.strictEqual(item.className, "mentioned");

        this.set(
          "notification",
          getNotification({
            notification_type: NOTIFICATION_TYPES.private_message,
          })
        );
        await settled();

        item = query("li");
        assert.strictEqual(
          item.className,
          "private-message",
          "replaces underscores in type name with dashes"
        );
      },
    });

    componentTest(
      "pushes is-warning to the classList if the notification originates from a warning PM",
      {
        template,

        beforeEach() {
          this.set("notification", getNotification({ is_warning: true }));
        },

        async test(assert) {
          assert.ok(exists("li.is-warning"));
        },
      }
    );

    componentTest(
      "doesn't push is-warning to the classList if the notification doesn't originate from a warning PM",
      {
        template,

        beforeEach() {
          this.set("notification", getNotification());
        },

        async test(assert) {
          assert.ok(!exists("li.is-warning"));
          assert.ok(exists("li"));
        },
      }
    );

    componentTest(
      "the item's href links to the topic that the notification originates from",
      {
        template,

        beforeEach() {
          this.set("notification", getNotification());
        },

        async test(assert) {
          const link = query("li a");
          assert.ok(link.href.endsWith("/t/this-is-fancy-title/449/113"));
        },
      }
    );

    componentTest(
      "the item's href links to the group messages if the notification is for a group messages",
      {
        template,

        beforeEach() {
          this.set(
            "notification",
            getNotification({
              topic_id: null,
              post_number: null,
              slug: null,
              data: {
                group_id: 33,
                group_name: "grouperss",
                username: "ossaama",
              },
            })
          );
        },

        async test(assert) {
          const link = query("li a");
          assert.ok(link.href.endsWith("/u/ossaama/messages/grouperss"));
        },
      }
    );

    componentTest("the item's link has a title for accessibility", {
      template,

      beforeEach() {
        this.set("notification", getNotification());
      },

      async test(assert) {
        const link = query("li a");
        assert.strictEqual(
          link.title,
          I18n.t("notifications.titles.mentioned")
        );
      },
    });

    componentTest("has 2 spans: one for label and one for description", {
      template,

      beforeEach() {
        this.set("notification", getNotification());
      },

      async test(assert) {
        const spans = queryAll("li a span");
        assert.strictEqual(spans.length, 2);

        assert.strictEqual(
          spans[0].textContent.trim(),
          "osama",
          "the first span (label) defaults to username"
        );

        assert.strictEqual(
          spans[1].textContent.trim(),
          "This is fancy title <a>!",
          "the second span (description) defaults to the fancy_title"
        );
      },
    });

    componentTest(
      "the description falls back to topic_title from data if fancy_title is absent",
      {
        template,

        beforeEach() {
          this.set(
            "notification",
            getNotification({
              fancy_title: null,
            })
          );
        },

        async test(assert) {
          const span = query("li a span:nth-of-type(2)");

          assert.strictEqual(
            span.textContent.trim(),
            "this is title before it becomes fancy <a>!",
            "topic_title from data is rendered safely"
          );
        },
      }
    );

    componentTest("fancy_title can be decorated via the plugin API", {
      template,

      beforeEach() {
        withPluginApi("0.1", (api) => {
          api.registerUserMenuTopicTitleDecorator((fancy_title) => {
            return fancy_title.replaceAll("fancy", "ycnaf");
          });
          api.registerUserMenuTopicTitleDecorator((fancy_title) => {
            return fancy_title.replaceAll("title", "eltit");
          });
        });
        this.set("notification", getNotification());
      },

      async test(assert) {
        const span = query("li a span:nth-of-type(2)");

        assert.strictEqual(
          span.textContent.trim(),
          "This is ycnaf eltit <a>!",
          "fancy_title decorators registered via plugin API are applied"
        );
      },
    });

    componentTest("fancy_title is emoji-unescaped", {
      template,

      beforeEach() {
        this.set(
          "notification",
          getNotification({
            fancy_title: "title with emoji :phone:",
          })
        );
      },

      async test(assert) {
        assert.ok(
          exists("li a span:nth-of-type(2) img.emoji"),
          "emojis are unescaped when fancy_title is used for description"
        );
      },
    });

    componentTest("topic_title from data is not emoji-unescaped", {
      template,

      beforeEach() {
        this.set(
          "notification",
          getNotification({
            fancy_title: null,
            data: {
              topic_title: "unsafe title with unescaped emoji :phone:",
            },
          })
        );
      },

      async test(assert) {
        const span = query("li a span:nth-of-type(2)");

        assert.strictEqual(
          span.textContent.trim(),
          "unsafe title with unescaped emoji :phone:",
          "emojis aren't unescaped when topic title is not safe"
        );
        assert.strictEqual(queryAll("img").length, 0);
      },
    });
  }
);
