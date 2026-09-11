/** The single owner of a touch sequence in the browser shell. */
export enum TouchOwner {
  NONE = 'none',
  TAB_BAR_BUTTON = 'tabBarButton',
  TAB_BAR_PAN = 'tabBarPan',
  PAGE = 'page'
}

export interface TouchOwnershipState {
  owner: TouchOwner;
  buttonId: string;
  startInTabBar: boolean;
  buttonClickCancelled: boolean;
}

/** Assign ownership once at Down; the owner never changes to the page later. */
export function beginTouchOwnership(startInTabBar: boolean, buttonId: string): TouchOwnershipState {
  if (!startInTabBar) {
    return {
      owner: TouchOwner.PAGE,
      buttonId: '',
      startInTabBar: false,
      buttonClickCancelled: false
    };
  }
  return {
    owner: buttonId.length > 0 ? TouchOwner.TAB_BAR_BUTTON : TouchOwner.TAB_BAR_PAN,
    buttonId,
    startInTabBar: true,
    buttonClickCancelled: false
  };
}

/** Promote a button stream to the TabBar pan stream after horizontal slop. */
export function cancelButtonClickForPan(state: TouchOwnershipState): TouchOwnershipState {
  if (!state.startInTabBar || state.owner === TouchOwner.PAGE || state.owner === TouchOwner.NONE) {
    return state;
  }
  return {
    owner: TouchOwner.TAB_BAR_PAN,
    buttonId: state.buttonId,
    startInTabBar: true,
    buttonClickCancelled: state.buttonId.length > 0
  };
}

/** Button actions are dispatched only by the native Button onClick path. */
export function shouldDispatchButtonClick(state: TouchOwnershipState): boolean {
  return state.owner === TouchOwner.TAB_BAR_BUTTON && !state.buttonClickCancelled;
}
