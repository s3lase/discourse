import GlimmerComponent from "discourse/components/glimmer";
import { cached, tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { LIKE_NOTIFICATION_FREQUENCY_TYPE } from "discourse/models/user";
import { WITH_REMINDER_ICON } from "discourse/models/bookmark";
import { consolePrefix } from "discourse/lib/source-identifier";

const DefaultTabId = "all-notifications";
const DefaultPanelComponent = "user-menu/notifications-list";

const ReviewQueueTabId = "review-queue";

let _customTabs = [];

export function registerUserMenuTab(config) {
  let valid = true;
  ["id", "icon", "panelComponent"].forEach((attr) => {
    if (!config[attr]) {
      valid = false;
      // eslint-disable-next-line no-console
      console.error(
        consolePrefix(),
        `the \`registerUserMenuTab\` API requires an object with \`${attr}\` attribute, but there is no such attribute for the following tab:`,
        config
      );
    }
  });
  if (!valid) {
    return;
  }
  _customTabs.push(config);
}

export function resetUserMenuTabs() {
  _customTabs = [];
}

export default class UserMenu extends GlimmerComponent {
  @tracked currentTabId = DefaultTabId;
  @tracked currentPanelComponent = DefaultPanelComponent;

  @cached
  get topTabs() {
    const tabs = this._coreTopTabs;
    const reviewQueueTabIndex = tabs.findIndex(
      (tab) => tab.id === ReviewQueueTabId
    );
    _customTabs.forEach((config) => {
      if (
        !config.shouldDisplay ||
        config.shouldDisplay(this.currentUser, this.siteSettings, this.site)
      ) {
        const tab = {
          id: config.id,
          icon: config.icon,
          panelComponent: config.panelComponent,
        };
        if (config.notificationTypesForCount) {
          tab.count = 0;
          config.notificationTypesForCount.forEach((type) => {
            tab.count += this._getUnreadCountForType(type);
          });
        }
        // ensure the review queue tab is always last
        if (reviewQueueTabIndex === -1) {
          tabs.push(tab);
        } else {
          tabs.insertAt(tabs.length - 1, tab);
        }
      }
    });
    return tabs.map((tab, index) => {
      tab.position = index;
      return tab;
    });
  }

  @cached
  get bottomTabs() {
    const topTabsLength = this.topTabs.length;
    return this._coreBottomTabs.map((tab, index) => {
      tab.position = index + topTabsLength;
      return tab;
    });
  }

  get _coreTopTabs() {
    const list = [
      {
        id: DefaultTabId,
        icon: "bell",
        panelComponent: DefaultPanelComponent,
      },
      {
        id: "replies",
        icon: "reply",
        panelComponent: "user-menu/replies-notifications-list",
      },
      {
        id: "mentions",
        icon: "at",
        panelComponent: "user-menu/mentions-notifications-list",
      },
    ];

    if (
      this.currentUser.like_notification_frequency !==
      LIKE_NOTIFICATION_FREQUENCY_TYPE.never
    ) {
      list.push({
        id: "likes",
        icon: "heart",
        panelComponent: "user-menu/likes-notifications-list",
      });
    }

    list.push(
      {
        id: "pms",
        icon: "far-envelope",
        panelComponent: "user-menu/pms-notifications-list",
        count: this._getUnreadCountForType("private_message"),
      },
      {
        id: "bookmarks",
        icon: WITH_REMINDER_ICON,
        panelComponent: "user-menu/bookmarks-notifications-list",
        count: this._getUnreadCountForType("bookmark_reminder"),
      },
      {
        id: "badges",
        icon: "certificate",
        panelComponent: "user-menu/badges-notifications-list",
      }
    );

    if (this.currentUser.can_review) {
      list.push({
        id: ReviewQueueTabId,
        icon: "flag",
        panelComponent: "user-menu/reviewables-list",
        // we're retrieving the value with get() so that Ember tracks the property
        // and re-renders the UI when it changes
        count: this.currentUser.get("reviewable_count"),
      });
    }

    return list;
  }

  get _coreBottomTabs() {
    return [
      {
        id: "preferences",
        icon: "user-cog",
        href: `${this.currentUser.path}/preferences`,
      },
    ];
  }

  _getUnreadCountForType(type) {
    let key = "grouped_unread_high_priority_notifications.";
    key += `${this.site.notification_types[type]}`;
    // we're retrieving the value with get() so that Ember tracks the property
    // and re-renders the UI when it changes
    return this.currentUser.get(key) || 0;
  }

  @action
  changeTab(tab) {
    if (this.currentTabId !== tab.id) {
      this.currentTabId = tab.id;
      this.currentPanelComponent = tab.panelComponent || DefaultPanelComponent;
    }
  }
}
