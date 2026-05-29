import { apiInitializer } from "discourse/lib/api";

const TOOLBAR_BUTTON_SELECTOR = ".d-editor-button-bar .toolbar__button";
const MENTION_AUTOCOMPLETE_SELECTOR = ".autocomplete.ac-user";
const PATCH_DEBOUNCE_MS = 60;
const MENTION_DEBOUNCE_MS = 80;
const MENTION_LIVE_REGION_ID = "aria-patches-mention-live-region";

function debugLog(event, payload = {}) {
  if (!settings?.aria_patches_debug) {
    return;
  }

  console.log(`[aria-patches] ${event}`, payload);
}

function cleanedAriaLabel(title) {
  if (!title) {
    return "";
  }

  // Remove trailing shortcut hints like " (Ctrl B)" / " (Strg B)".
  return title.replace(/\s*\([^)]*\)\s*$/, "").trim();
}

function getAccessibleText(element) {
  return (
    element?.getAttribute("aria-label") ||
    element?.getAttribute("title") ||
    (element?.textContent || "")
  )
    .replace(/\s+/g, " ")
    .trim();
}

function setAriaLabelFromTitle(button) {
  const title = button.getAttribute("title");

  if (!title) {
    return;
  }

  const nextAriaLabel = cleanedAriaLabel(title) || title;

  if (button.getAttribute("aria-label") !== nextAriaLabel) {
    button.setAttribute("aria-label", nextAriaLabel);
    debugLog("set-aria-label", {
      classes: button.className,
      value: nextAriaLabel,
    });
  }
}

function ensureScreenReaderLabelFromTitle(button) {
  const title = button.getAttribute("title");
  if (!title) {
    return;
  }

  const srText = cleanedAriaLabel(title) || title;
  if (!srText) {
    return;
  }

  const existing = button.querySelector(":scope > .aria-patches-sr-label");
  const srIdBase =
    button.getAttribute("data-identifier") ||
    button.id ||
    button.className.replace(/\s+/g, "-");
  const srId = `aria-patches-sr-${srIdBase}`;

  const srLabel = existing || document.createElement("span");
  srLabel.className = "aria-patches-sr-label";
  srLabel.id = srId;
  srLabel.textContent = srText;
  srLabel.style.position = "absolute";
  srLabel.style.width = "1px";
  srLabel.style.height = "1px";
  srLabel.style.padding = "0";
  srLabel.style.margin = "-1px";
  srLabel.style.overflow = "hidden";
  srLabel.style.clip = "rect(0, 0, 0, 0)";
  srLabel.style.whiteSpace = "nowrap";
  srLabel.style.border = "0";

  if (!existing) {
    button.appendChild(srLabel);
  }

  let changed = false;

  if (!existing) {
    changed = true;
  }

  if (button.getAttribute("aria-labelledby") !== srId) {
    button.setAttribute("aria-labelledby", srId);
    changed = true;
  }

  if (changed) {
    debugLog("set-aria-labelledby", {
      classes: button.className,
      id: srId,
      text: srText,
    });
  }
}

function hideSingleLetterLabelForAT(button) {
  const label = button.querySelector(":scope > .d-button-label");
  if (!label) {
    return;
  }

  const text = (label.textContent || "").trim();
  const title = button.getAttribute("title");
  const fallbackAriaLabel = cleanedAriaLabel(title) || title || "";

  if (text.length === 1) {
    let changed = false;

    if (!button.getAttribute("aria-label") && fallbackAriaLabel) {
      button.setAttribute("aria-label", fallbackAriaLabel);
      changed = true;
    }

    if (label.getAttribute("aria-hidden") !== "true") {
      label.setAttribute("aria-hidden", "true");
      changed = true;
    }

    if (label.getAttribute("role") !== "presentation") {
      label.setAttribute("role", "presentation");
      changed = true;
    }

    if (changed) {
      debugLog("hide-single-letter-label", {
        classes: button.className,
        text,
        ariaLabel: button.getAttribute("aria-label"),
      });
    }

    return;
  }

  let changed = false;

  if (label.getAttribute("aria-hidden") === "true") {
    label.removeAttribute("aria-hidden");
    changed = true;
  }

  if (label.getAttribute("role") === "presentation") {
    label.removeAttribute("role");
    changed = true;
  }

  if (changed) {
    debugLog("show-label-for-at", {
      classes: button.className,
      text,
    });
  }
}

function removeAriaKeyShortcuts(button) {
  if (!button.hasAttribute("aria-keyshortcuts")) {
    return;
  }

  button.removeAttribute("aria-keyshortcuts");
  debugLog("remove-aria-keyshortcuts", {
    classes: button.className,
  });
}

function patchToolbarButton(button) {
  setAriaLabelFromTitle(button);
  removeAriaKeyShortcuts(button);
  ensureScreenReaderLabelFromTitle(button);
  hideSingleLetterLabelForAT(button);

  if (button.classList.contains("toolbar-popup-menu-options")) {
    if (button.getAttribute("aria-haspopup") !== "menu") {
      button.setAttribute("aria-haspopup", "menu");
      debugLog("set-aria-haspopup", {
        classes: button.className,
      });
    }
  }
}

function patchAllToolbarButtons() {
  document.querySelectorAll(TOOLBAR_BUTTON_SELECTOR).forEach((button) => {
    patchToolbarButton(button);
  });
}

function ensureMentionLiveRegion() {
  let liveRegion = document.getElementById(MENTION_LIVE_REGION_ID);

  if (liveRegion) {
    return liveRegion;
  }

  liveRegion = document.createElement("div");
  liveRegion.id = MENTION_LIVE_REGION_ID;
  liveRegion.setAttribute("role", "status");
  liveRegion.setAttribute("aria-live", "polite");
  liveRegion.setAttribute("aria-atomic", "true");
  liveRegion.style.position = "absolute";
  liveRegion.style.width = "1px";
  liveRegion.style.height = "1px";
  liveRegion.style.padding = "0";
  liveRegion.style.margin = "-1px";
  liveRegion.style.overflow = "hidden";
  liveRegion.style.clip = "rect(0, 0, 0, 0)";
  liveRegion.style.whiteSpace = "nowrap";
  liveRegion.style.border = "0";

  document.body.appendChild(liveRegion);
  return liveRegion;
}

function patchMentionAutocompleteA11y(container) {
  const list = container.querySelector("ul");
  if (list) {
    list.setAttribute("role", "listbox");
  }

  const options = container.querySelectorAll("li a");
  options.forEach((option) => {
    option.setAttribute("role", "option");
    option.setAttribute("aria-selected", option.classList.contains("selected") ? "true" : "false");
  });
}

function buildMentionAnnouncement(container) {
  const options = Array.from(container.querySelectorAll("li a"));
  const count = options.length;

  if (count === 0) {
    return "No mention suggestions.";
  }

  const selected = container.querySelector("li a.selected");
  if (selected) {
    const selectedText = getAccessibleText(selected);
    if (selectedText) {
      return `${count} mention suggestions. Selected ${selectedText}.`;
    }
  }

  return `${count} mention suggestions available.`;
}

function patchMentionAutocompletes(state) {
  const liveRegion = ensureMentionLiveRegion();
  const containers = document.querySelectorAll(MENTION_AUTOCOMPLETE_SELECTOR);

  if (containers.length === 0) {
    if (state.lastAnnouncement) {
      liveRegion.textContent = "Mention suggestions closed.";
      state.lastAnnouncement = "";
      debugLog("mention-live-close");
    }
    return;
  }

  containers.forEach((container) => {
    patchMentionAutocompleteA11y(container);
    const message = buildMentionAnnouncement(container);

    if (message && message !== state.lastAnnouncement) {
      liveRegion.textContent = message;
      state.lastAnnouncement = message;
      debugLog("mention-live-announce", { message });
    }
  });
}

function observeMentionAutocomplete() {
  let isPatching = false;
  let debounceTimer = null;
  let bodyObserver = null;
  let visibilityHandler = null;
  const containerObservers = new Map();
  const state = {
    lastAnnouncement: "",
  };

  const schedulePatch = () => {
    if (document.hidden) {
      return;
    }

    if (debounceTimer) {
      clearTimeout(debounceTimer);
    }

    debounceTimer = setTimeout(() => {
      debounceTimer = null;
      runPatch();
    }, MENTION_DEBOUNCE_MS);
  };

  const syncContainerObservers = () => {
    const currentContainers = new Set(
      document.querySelectorAll(MENTION_AUTOCOMPLETE_SELECTOR)
    );

    currentContainers.forEach((container) => {
      if (containerObservers.has(container)) {
        return;
      }

      const observer = new MutationObserver(() => {
        schedulePatch();
      });

      observer.observe(container, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ["class", "title"],
      });

      containerObservers.set(container, observer);
    });

    Array.from(containerObservers.keys()).forEach((container) => {
      if (currentContainers.has(container)) {
        return;
      }

      containerObservers.get(container)?.disconnect();
      containerObservers.delete(container);
    });
  };

  const runPatch = () => {
    if (isPatching || document.hidden) {
      return;
    }

    isPatching = true;
    try {
      syncContainerObservers();
      patchMentionAutocompletes(state);
    } finally {
      isPatching = false;
    }
  };

  bodyObserver = new MutationObserver((mutations) => {
    const hasRelevantChildMutation = mutations.some(
      (mutation) =>
        mutation.type === "childList" &&
        ([...mutation.addedNodes, ...mutation.removedNodes].some(
          (node) =>
            node.nodeType === Node.ELEMENT_NODE &&
            (node.matches?.(MENTION_AUTOCOMPLETE_SELECTOR) ||
              node.querySelector?.(MENTION_AUTOCOMPLETE_SELECTOR))
        ) || mutation.target.closest?.(MENTION_AUTOCOMPLETE_SELECTOR))
    );

    if (hasRelevantChildMutation) {
      schedulePatch();
    }
  });

  bodyObserver.observe(document.body, {
    childList: true,
    subtree: true,
  });

  visibilityHandler = () => {
    if (!document.hidden) {
      schedulePatch();
    }
  };

  document.addEventListener("visibilitychange", visibilityHandler);
  runPatch();

  return {
    disconnect() {
      bodyObserver?.disconnect();
      containerObservers.forEach((observer) => observer.disconnect());
      containerObservers.clear();

      if (debounceTimer) {
        clearTimeout(debounceTimer);
      }

      if (visibilityHandler) {
        document.removeEventListener("visibilitychange", visibilityHandler);
      }
    },
  };
}

function observeToolbar() {
  let isPatching = false;
  let debounceTimer = null;
  let visibilityHandler = null;

  const schedulePatch = () => {
    if (document.hidden) {
      return;
    }

    if (debounceTimer) {
      clearTimeout(debounceTimer);
    }

    debounceTimer = setTimeout(() => {
      debounceTimer = null;
      runPatch();
    }, PATCH_DEBOUNCE_MS);
  };

  const runPatch = () => {
    if (isPatching || document.hidden) {
      return;
    }

    isPatching = true;
    try {
      patchAllToolbarButtons();
    } finally {
      isPatching = false;
    }
  };

  const observer = new MutationObserver((mutations) => {
    const hasRelevantChildMutation = mutations.some(
      (mutation) =>
        mutation.type === "childList" &&
        ([...mutation.addedNodes, ...mutation.removedNodes].some(
          (node) =>
            node.nodeType === Node.ELEMENT_NODE &&
            (node.matches?.(TOOLBAR_BUTTON_SELECTOR) ||
              node.querySelector?.(TOOLBAR_BUTTON_SELECTOR) ||
              node.matches?.(".d-editor-button-bar") ||
              node.querySelector?.(".d-editor-button-bar"))
        ) || mutation.target.closest?.(".d-editor-button-bar"))
    );

    if (hasRelevantChildMutation) {
      schedulePatch();
    }
  });

  observer.observe(document.body, {
    childList: true,
    subtree: true,
  });

  visibilityHandler = () => {
    if (!document.hidden) {
      schedulePatch();
    }
  };

  document.addEventListener("visibilitychange", visibilityHandler);

  return {
    disconnect() {
      observer.disconnect();

      if (debounceTimer) {
        clearTimeout(debounceTimer);
      }

      if (visibilityHandler) {
        document.removeEventListener("visibilitychange", visibilityHandler);
      }
    },
  };
}

export default apiInitializer((api) => {
  let observer = null;
  let mentionObserver = null;

  api.onPageChange(() => {
    if (observer) {
      observer.disconnect();
      observer = null;
    }

    if (mentionObserver) {
      mentionObserver.disconnect();
      mentionObserver = null;
    }

    patchAllToolbarButtons();
    observer = observeToolbar();
    mentionObserver = observeMentionAutocomplete();

    debugLog("started");
  });
});
