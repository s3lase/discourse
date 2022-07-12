import { test } from "qunit";

import { click, visit } from "@ember/test-helpers";
import {
  acceptance,
  exists,
  query,
  queryAll,
} from "discourse/tests/helpers/qunit-helpers";
import { withPluginApi } from "discourse/lib/plugin-api";

acceptance("Sidebar - section API", function (needs) {
  needs.user({ experimental_sidebar_enabled: true });

  test("Multiple header actions and links", async function (assert) {
    withPluginApi("1.3.0", (api) => {
      api.addSidebarSection(
        (BaseCustomSidebarSection, BaseCustomSidebarSectionLink) => {
          return class extends BaseCustomSidebarSection {
            get name() {
              return "chat-channels";
            }

            get route() {
              return "chat";
            }

            get title() {
              return "chat channels title";
            }

            get text() {
              return "chat channels text";
            }

            get actionsIcon() {
              return "cog";
            }

            get actions() {
              return [
                {
                  id: "browseChannels",
                  title: "Browse channels",
                  action: () => {},
                },
                {
                  id: "settings",
                  title: "Settings",
                  action: () => {},
                },
              ];
            }

            get links() {
              return [
                new (class extends BaseCustomSidebarSectionLink {
                  get name() {
                    "random-channel";
                  }
                  get route() {
                    return "chat.channel";
                  }
                  get model() {
                    return {
                      channelId: "1",
                      channelTitle: "random channel",
                    };
                  }
                  get title() {
                    return "random channel title";
                  }
                  get text() {
                    return "random channel text";
                  }
                  get prefixIcon() {
                    return "hashtag";
                  }
                  get prefixIconColor() {
                    return "FF0000";
                  }
                  get prefixIconBadge() {
                    return "lock";
                  }
                  get suffixIcon() {
                    return "circle";
                  }
                  get suffixCssClass() {
                    return "unread";
                  }
                })(),
                new (class extends BaseCustomSidebarSectionLink {
                  get name() {
                    "dev-channel";
                  }
                  get route() {
                    return "chat.channel";
                  }
                  get model() {
                    return {
                      channelId: "2",
                      channelTitle: "dev channel",
                    };
                  }
                  get title() {
                    return "dev channel title";
                  }
                  get text() {
                    return "dev channel text";
                  }
                  get prefixIconColor() {
                    return "alert";
                  }
                  get prefixIcon() {
                    return "hashtag";
                  }
                })(),
              ];
            }
          };
        }
      );
    });

    await visit("/");
    assert.strictEqual(
      query(".sidebar-section-chat-channels .sidebar-section-header a").title,
      "chat channels title",
      "displays header with correct title attribute"
    );
    assert.strictEqual(
      query(
        ".sidebar-section-chat-channels .sidebar-section-header a"
      ).textContent.trim(),
      "chat channels text",
      "displays header with correct text"
    );
    await click(".edit-channels-dropdown summary");
    assert.strictEqual(
      queryAll(".edit-channels-dropdown .select-kit-collection li").length,
      2,
      "displays two actions"
    );
    const $actions = queryAll(
      ".edit-channels-dropdown .select-kit-collection li"
    );
    assert.strictEqual(
      $actions[0].textContent.trim(),
      "Browse channels",
      "displays first header action with correct text"
    );
    assert.strictEqual(
      $actions[1].textContent.trim(),
      "Settings",
      "displays second header action with correct text"
    );

    const $links = queryAll(
      ".sidebar-section-chat-channels .sidebar-section-content a"
    );
    assert.strictEqual(
      $links[0].textContent.trim(),
      "random channel text",
      "displays first link with correct text"
    );
    assert.strictEqual(
      $links[0].title,
      "random channel title",
      "displays first link with correct title attribute"
    );
    assert.strictEqual(
      $links[0].children.item(0).style.color,
      "rgb(255, 0, 0)",
      "has correct prefix color"
    );
    assert.strictEqual(
      $($links[0].children.item(0).children.item(0)).hasClass("d-icon-hashtag"),
      true,
      "displays prefix icon"
    );
    assert.strictEqual(
      $($links[0].children.item(0).children.item(1)).hasClass("d-icon-lock"),
      true,
      "displays prefix icon badge"
    );
    assert.strictEqual(
      $($links[0].children.item(2).children.item(0)).hasClass("d-icon-circle"),
      true,
      "displays suffix icon"
    );

    assert.strictEqual(
      $links[1].textContent.trim(),
      "dev channel text",
      "displays second link with correct text"
    );
    assert.strictEqual(
      $links[1].title,
      "dev channel title",
      "displays second link with correct title attribute"
    );
    assert.strictEqual(
      $links[1].children.item(0).style.color,
      "",
      "has no color style when value is invalid"
    );
  });

  test("Single header action and no links", async function (assert) {
    withPluginApi("1.3.1", (api) => {
      api.addSidebarSection((BaseCustomSidebarSection) => {
        return class extends BaseCustomSidebarSection {
          get name() {
            return "chat-channels";
          }

          get route() {
            return "chat";
          }

          get title() {
            return "chat channels title";
          }

          get text() {
            return "chat channels text";
          }

          get actionsIcon() {
            return "cog";
          }

          get actions() {
            return [
              {
                id: "browseChannels",
                title: "Browse channels",
                action: () => {},
              },
            ];
          }

          get links() {
            return [];
          }
        };
      });
    });

    await visit("/");
    assert.strictEqual(
      query(
        ".sidebar-section-chat-channels .sidebar-section-header a"
      ).textContent.trim(),
      "chat channels text",
      "displays header with correct text"
    );
    assert.ok(
      exists("button.sidebar-section-header-button"),
      "displays single header action button"
    );
    assert.ok(
      !exists(".sidebar-section-chat-channels .sidebar-section-content a"),
      "displays no links"
    );
  });
});
