/**
 * Base class representing a sidebar section header interface.
 */
export default class BaseCustomSidebarSection {
  /**
   * @returns {string} The name of the section header. Needs to be dasherized and lowercase.
   */
  get name() {
    this._notImplemented();
  }

  /**
   * @returns {string} Title for the header
   */
  get title() {
    this._notImplemented();
  }

  /**
   * @returns {string} Text for the header
   */
  get text() {
    this._notImplemented();
  }

  /**
   * @returns {array} Actions for header options button
   */
  get actions() {}

  /**
   * @returns {string} Icon for header options button
   */
  get actionsIcon() {}

  /**
   * @returns {array} Links for section, instances of BaseCustomSidebarSectionLink
   */
  get links() {}

  _notImplemented() {
    throw "not implemented";
  }
}
