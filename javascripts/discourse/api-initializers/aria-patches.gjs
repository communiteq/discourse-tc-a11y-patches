import { apiInitializer } from "discourse/lib/api";
import { i18n } from "discourse-i18n";

const TOOLBAR_BUTTON_SELECTOR = ".d-editor-button-bar .toolbar__button";
const MENTION_AUTOCOMPLETE_SELECTOR = ".autocomplete.ac-user";
const SEARCH_RESULT_TOPIC_SELECTOR = ".search-result-topic .topic";
const ADVANCED_SEARCH_RESULT_TOPIC_SELECTOR =
  ".search-results .fps-result .fps-topic .topic";
const PATCH_DEBOUNCE_MS = 60;
const MENTION_DEBOUNCE_MS = 80;
const SEARCH_DEBOUNCE_MS = 80;
const MENTION_LIVE_REGION_ID = "aria-patches-mention-live-region";
let searchTitleIdCounter = 0;

function isComposerTitleFocused() {
  const active = document.activeElement;

  if (!active) {
    return false;
  }

  return Boolean(
    active.matches?.("#reply-title, .composer-fields .title-input")
  );
}

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

function getSearchResultTopicLabel(topicElement) {
  const preferredText =
    topicElement.querySelector(".first-line .topic-title a span")?.textContent ||
    topicElement.querySelector(".first-line .topic-title a")?.textContent ||
    topicElement.querySelector("a .topic-title")?.textContent ||
    topicElement.querySelector("a")?.textContent ||
    "";

  return preferredText.replace(/\s+/g, " ").trim();
}

function patchSearchResultTopicLabel(topicElement) {
  const label = getSearchResultTopicLabel(topicElement);
  if (!label) {
    return;
  }

  const resultContainer = topicElement.closest(".search-result-topic, .fps-result");
  const target = resultContainer || topicElement;
  const topicTitleElement =
    topicElement.querySelector(".first-line .topic-title") ||
    topicElement.querySelector(".topic-title");
  const topicLink =
    topicElement.querySelector("a.search-link") ||
    topicElement.querySelector(".first-line .topic-title a") ||
    topicElement.querySelector("a");

  let changed = false;

  if (topicElement !== target && topicElement.hasAttribute("aria-label")) {
    topicElement.removeAttribute("aria-label");
    changed = true;
  }

  if (target.hasAttribute("aria-label")) {
    target.removeAttribute("aria-label");
    changed = true;
  }

  const topicId =
    topicElement.closest(".fps-topic")?.getAttribute("data-topic-id") ||
    topicElement
      .querySelector(".topic-title[data-topic-id]")
      ?.getAttribute("data-topic-id") ||
    target.getAttribute("data-topic-id") ||
    "";
  const fallbackId =
    target.dataset.ariaPatchesResultId || `generated-${++searchTitleIdCounter}`;
  const stableIdPart = topicId || fallbackId;

  if (!topicId && !target.dataset.ariaPatchesResultId) {
    target.dataset.ariaPatchesResultId = fallbackId;
  }

  const srLabelId = `aria-patches-search-result-label-${stableIdPart}`;
  let srLabel = target.querySelector(":scope > .aria-patches-search-sr-label");

  if (!srLabel) {
    srLabel = document.createElement("span");
    srLabel.className = "aria-patches-search-sr-label";
    srLabel.style.position = "absolute";
    srLabel.style.width = "1px";
    srLabel.style.height = "1px";
    srLabel.style.padding = "0";
    srLabel.style.margin = "-1px";
    srLabel.style.overflow = "hidden";
    srLabel.style.clip = "rect(0, 0, 0, 0)";
    srLabel.style.whiteSpace = "nowrap";
    srLabel.style.border = "0";
    target.appendChild(srLabel);
    changed = true;
  }

  if (srLabel.id !== srLabelId) {
    srLabel.id = srLabelId;
    changed = true;
  }

  if (srLabel.textContent !== label) {
    srLabel.textContent = label;
    changed = true;
  }

  if (target.getAttribute("aria-labelledby") !== srLabel.id) {
    target.setAttribute("aria-labelledby", srLabel.id);
    changed = true;
  }

  if (topicLink && topicLink.getAttribute("aria-label") !== label) {
    topicLink.setAttribute("aria-label", label);
    changed = true;
  }

  // Keep result announcement focused on the topic title by hiding secondary
  // metadata blocks from assistive tech for search result containers.
  const metadataSelectors = target.classList.contains("fps-result")
    ? [".search-category", ".blurb", ".like-count"]
    : [".second-line"];

  metadataSelectors.forEach((selector) => {
    const metadata = target.querySelector(selector);
    if (metadata && metadata.getAttribute("aria-hidden") !== "true") {
      metadata.setAttribute("aria-hidden", "true");
      changed = true;
    }
  });

  // In full-page search entries, NVDA often picks the avatar/user link first and
  // skips the topic label context. Hide that decorative author block from AT so
  // the topic result label/link is announced instead.
  if (target.classList.contains("fps-result")) {
    const authorWrapper = target.querySelector(":scope > .author");
    if (authorWrapper && authorWrapper.getAttribute("aria-hidden") !== "true") {
      authorWrapper.setAttribute("aria-hidden", "true");
      changed = true;
    }
  }

  if (changed) {
    debugLog("set-search-result-topic-label", {
      label,
      targetClass: target.className,
      hasTopicLink: Boolean(topicLink),
    });
  }
}

function patchAllSearchResultTopicLabels() {
  document.querySelectorAll(SEARCH_RESULT_TOPIC_SELECTOR).forEach((topicElement) => {
    patchSearchResultTopicLabel(topicElement);
  });

  document
    .querySelectorAll(ADVANCED_SEARCH_RESULT_TOPIC_SELECTOR)
    .forEach((topicElement) => {
      patchSearchResultTopicLabel(topicElement);
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

function getMentionAutocompleteState(container) {
  const options = Array.from(container.querySelectorAll("li a"));
  const count = options.length;
  const labels = options.map((option) => getAccessibleText(option));

  if (count === 0) {
    return {
      count,
      labels,
      selectedText: "",
    };
  }

  const selected = container.querySelector("li a.selected");
  return {
    count,
    labels,
    selectedText: selected ? getAccessibleText(selected) : "",
  };
}

function buildMentionAnnouncement(nextState, previousState) {
  if (nextState.count === 0) {
    return "";
  }

  const labelsChanged =
    nextState.count !== previousState.lastCount ||
    nextState.labels.join("|") !== previousState.lastLabels.join("|");

  if (labelsChanged) {
    if (nextState.selectedText) {
      return i18n(themePrefix("mention_suggestions.available_selected"), {
        count: nextState.count,
        selected_text: nextState.selectedText,
      });
    }

    return i18n(themePrefix("mention_suggestions.available"), {
      count: nextState.count,
    });
  }

  if (
    nextState.selectedText &&
    nextState.selectedText !== previousState.lastSelectedText
  ) {
    return i18n(themePrefix("mention_suggestions.selected"), {
      selected_text: nextState.selectedText,
    });
  }

  return "";
}

function patchMentionAutocompletes(state) {
  const liveRegion = ensureMentionLiveRegion();
  const containers = document.querySelectorAll(MENTION_AUTOCOMPLETE_SELECTOR);

  if (containers.length === 0) {
    state.lastAnnouncement = "";
    state.lastCount = 0;
    state.lastLabels = [];
    state.lastSelectedText = "";
    return;
  }

  containers.forEach((container) => {
    patchMentionAutocompleteA11y(container);
    const nextState = getMentionAutocompleteState(container);

    if (nextState.count === 0) {
      state.lastCount = 0;
      state.lastLabels = [];
      state.lastSelectedText = "";
      state.lastAnnouncement = "";
      return;
    }

    const message = buildMentionAnnouncement(nextState, state);

    state.lastCount = nextState.count;
    state.lastLabels = nextState.labels;
    state.lastSelectedText = nextState.selectedText;

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
    lastCount: 0,
    lastLabels: [],
    lastSelectedText: "",
  };

  const schedulePatch = () => {
    if (document.hidden || isComposerTitleFocused()) {
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
    if (isPatching || document.hidden || isComposerTitleFocused()) {
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
    if (document.hidden || isComposerTitleFocused()) {
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
    if (isPatching || document.hidden || isComposerTitleFocused()) {
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

function observeSearchResultTopics() {
  let isPatching = false;
  let debounceTimer = null;
  let visibilityHandler = null;

  const schedulePatch = () => {
    if (document.hidden || isComposerTitleFocused()) {
      return;
    }

    if (debounceTimer) {
      clearTimeout(debounceTimer);
    }

    debounceTimer = setTimeout(() => {
      debounceTimer = null;
      runPatch();
    }, SEARCH_DEBOUNCE_MS);
  };

  const runPatch = () => {
    if (isPatching || document.hidden || isComposerTitleFocused()) {
      return;
    }

    isPatching = true;
    try {
      patchAllSearchResultTopicLabels();
    } finally {
      isPatching = false;
    }
  };

  const observer = new MutationObserver((mutations) => {
    const hasRelevantMutation = mutations.some(
      (mutation) =>
        mutation.type === "childList" &&
        ([...mutation.addedNodes, ...mutation.removedNodes].some(
          (node) =>
            node.nodeType === Node.ELEMENT_NODE &&
            (node.matches?.(SEARCH_RESULT_TOPIC_SELECTOR) ||
              node.querySelector?.(SEARCH_RESULT_TOPIC_SELECTOR) ||
              node.matches?.(ADVANCED_SEARCH_RESULT_TOPIC_SELECTOR) ||
              node.querySelector?.(ADVANCED_SEARCH_RESULT_TOPIC_SELECTOR) ||
              node.matches?.(".search-result-topic") ||
              node.querySelector?.(".search-result-topic") ||
              node.matches?.(".fps-result") ||
              node.querySelector?.(".fps-result"))
        ) ||
          mutation.target.closest?.(".search-result-topic") ||
          mutation.target.closest?.(".fps-result"))
    );

    if (hasRelevantMutation) {
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
  runPatch();

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
  let searchObserver = null;

  api.onPageChange(() => {
    if (observer) {
      observer.disconnect();
      observer = null;
    }

    if (mentionObserver) {
      mentionObserver.disconnect();
      mentionObserver = null;
    }

    if (searchObserver) {
      searchObserver.disconnect();
      searchObserver = null;
    }

    patchAllToolbarButtons();
    observer = observeToolbar();
    mentionObserver = observeMentionAutocomplete();
    searchObserver = observeSearchResultTopics();

    debugLog("started");
  });
});
