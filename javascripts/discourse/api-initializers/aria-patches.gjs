import { apiInitializer } from "discourse/lib/api";

const TOOLBAR_BUTTON_SELECTOR = ".d-editor-button-bar .toolbar__button";
const PATCH_DEBOUNCE_MS = 60;

function debugLog(enabled, event, payload = {}) {
  if (!enabled) {
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

function setAriaLabelFromTitle(button, debug) {
  const title = button.getAttribute("title");

  if (!title) {
    return;
  }

  const nextAriaLabel = cleanedAriaLabel(title) || title;

  if (button.getAttribute("aria-label") !== nextAriaLabel) {
    button.setAttribute("aria-label", nextAriaLabel);
    debugLog(debug, "set-aria-label", {
      classes: button.className,
      value: nextAriaLabel,
    });
  }
}

function ensureScreenReaderLabelFromTitle(button, debug) {
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

  if (button.getAttribute("aria-labelledby") !== srId) {
    button.setAttribute("aria-labelledby", srId);
  }

  debugLog(debug, "set-aria-labelledby", {
    classes: button.className,
    id: srId,
    text: srText,
  });
}

function hideSingleLetterLabelForAT(button, debug) {
  const label = button.querySelector(":scope > .d-button-label");
  if (!label) {
    return;
  }

  const text = (label.textContent || "").trim();
  const title = button.getAttribute("title");
  const fallbackAriaLabel = cleanedAriaLabel(title) || title || "";

  if (text.length === 1) {
    if (!button.getAttribute("aria-label") && fallbackAriaLabel) {
      button.setAttribute("aria-label", fallbackAriaLabel);
    }

    if (label.getAttribute("aria-hidden") !== "true") {
      label.setAttribute("aria-hidden", "true");
    }

    if (label.getAttribute("role") !== "presentation") {
      label.setAttribute("role", "presentation");
    }

    debugLog(debug, "hide-single-letter-label", {
      classes: button.className,
      text,
      ariaLabel: button.getAttribute("aria-label"),
    });

    return;
  }

  if (label.getAttribute("aria-hidden") === "true") {
    label.removeAttribute("aria-hidden");
  }

  if (label.getAttribute("role") === "presentation") {
    label.removeAttribute("role");
  }

  debugLog(debug, "show-label-for-at", {
    classes: button.className,
    text,
  });
}

function removeAriaKeyShortcuts(button, debug) {
  if (!button.hasAttribute("aria-keyshortcuts")) {
    return;
  }

  button.removeAttribute("aria-keyshortcuts");
  debugLog(debug, "remove-aria-keyshortcuts", {
    classes: button.className,
  });
}

function patchToolbarButton(button, debug) {
  setAriaLabelFromTitle(button, debug);
  removeAriaKeyShortcuts(button, debug);
  ensureScreenReaderLabelFromTitle(button, debug);
  hideSingleLetterLabelForAT(button, debug);

  if (button.classList.contains("toolbar-popup-menu-options")) {
    button.setAttribute("aria-haspopup", "menu");
    debugLog(debug, "set-aria-haspopup", {
      classes: button.className,
    });
  }
}

function patchAllToolbarButtons(debug) {
  document.querySelectorAll(TOOLBAR_BUTTON_SELECTOR).forEach((button) => {
    patchToolbarButton(button, debug);
  });
}

function observeToolbar(debug) {
  let isPatching = false;
  let debounceTimer = null;

  const runPatch = () => {
    if (isPatching) {
      return;
    }

    isPatching = true;
    try {
      patchAllToolbarButtons(debug);
    } finally {
      isPatching = false;
    }
  };

  const observer = new MutationObserver(() => {
    if (debounceTimer) {
      clearTimeout(debounceTimer);
    }

    debounceTimer = setTimeout(() => {
      debounceTimer = null;
      runPatch();
    }, PATCH_DEBOUNCE_MS);
  });

  observer.observe(document.body, {
    childList: true,
    subtree: true,
    attributes: true,
    // Watch source-ish mutations only; avoid observing aria-* writes done by this patcher.
    attributeFilter: ["title", "class", "data-identifier", "id"],
  });

  return {
    disconnect() {
      observer.disconnect();
      if (debounceTimer) {
        clearTimeout(debounceTimer);
      }
    },
  };
}

export default apiInitializer((api) => {
  let observer = null;

  api.onPageChange(() => {
    if (observer) {
      observer.disconnect();
      observer = null;
    }

    const debug = Boolean(settings.aria_patches_debug);

    patchAllToolbarButtons(debug);
    observer = observeToolbar(debug);

    debugLog(debug, "started");
  });
});
