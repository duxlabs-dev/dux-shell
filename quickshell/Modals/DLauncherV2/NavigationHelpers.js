.pragma library

function getFirstItemIndex(flatModel) {
    for (var i = 0; i < flatModel.length; i++) {
        if (!flatModel[i].isHeader)
            return i;
    }
    return 0;
}

function findNextNonHeaderIndex(flatModel, startIndex) {
    for (var i = startIndex; i < flatModel.length; i++) {
        if (!flatModel[i].isHeader)
            return i;
    }
    return -1;
}

function findPrevNonHeaderIndex(flatModel, startIndex) {
    for (var i = startIndex; i >= 0; i--) {
        if (!flatModel[i].isHeader)
            return i;
    }
    return -1;
}

function getSectionBounds(flatModel, sectionId) {
    if (flatModel._sectionBounds && flatModel._sectionBounds[sectionId])
        return flatModel._sectionBounds[sectionId];

    var start = -1, end = -1;
    for (var i = 0; i < flatModel.length; i++) {
        if (flatModel[i].isHeader && flatModel[i].section?.id === sectionId) {
            start = i + 1;
        } else if (start >= 0 && !flatModel[i].isHeader && flatModel[i].sectionId === sectionId) {
            end = i;
        } else if (start >= 0 && end >= 0 && flatModel[i].sectionId !== sectionId) {
            break;
        }
    }
    return {
        start: start,
        end: end,
        count: end >= start ? end - start + 1 : 0
    };
}

function getGridColumns(viewMode, gridColumns) {
    switch (viewMode) {
    case "tile":
        return 3;
    case "grid":
        return gridColumns;
    default:
        return 1;
    }
}

function calculateNextIndex(flatModel, selectedFlatIndex, sectionId, viewMode, gridColumns, getSectionViewModeFn) {
    if (flatModel.length === 0)
        return selectedFlatIndex;

    var entry = flatModel[selectedFlatIndex];
    if (!entry || entry.isHeader) {
        var next = findNextNonHeaderIndex(flatModel, selectedFlatIndex + 1);
        return next !== -1 ? next : selectedFlatIndex;
    }

    var actualViewMode = viewMode || getSectionViewModeFn(entry.sectionId);
    if (actualViewMode === "list") {
        var next = findNextNonHeaderIndex(flatModel, selectedFlatIndex + 1);
        return next !== -1 ? next : selectedFlatIndex;
    }

    var bounds = getSectionBounds(flatModel, entry.sectionId);
    var cols = getGridColumns(actualViewMode, gridColumns);
    var posInSection = selectedFlatIndex - bounds.start;
    var newPosInSection = posInSection + cols;

    if (newPosInSection < bounds.count) {
        return bounds.start + newPosInSection;
    }

    var currentRow = Math.floor(posInSection / cols);
    var lastRow = Math.floor((bounds.count - 1) / cols);
    if (currentRow < lastRow) {
        return bounds.start + bounds.count - 1;
    }

    var nextSection = findNextNonHeaderIndex(flatModel, bounds.end + 1);
    return nextSection !== -1 ? nextSection : selectedFlatIndex;
}

function calculatePrevIndex(flatModel, selectedFlatIndex, sectionId, viewMode, gridColumns, getSectionViewModeFn) {
    if (flatModel.length === 0)
        return selectedFlatIndex;

    var entry = flatModel[selectedFlatIndex];
    if (!entry || entry.isHeader) {
        var prev = findPrevNonHeaderIndex(flatModel, selectedFlatIndex - 1);
        return prev !== -1 ? prev : selectedFlatIndex;
    }

    var actualViewMode = viewMode || getSectionViewModeFn(entry.sectionId);
    if (actualViewMode === "list") {
        var prev = findPrevNonHeaderIndex(flatModel, selectedFlatIndex - 1);
        return prev !== -1 ? prev : selectedFlatIndex;
    }

    var bounds = getSectionBounds(flatModel, entry.sectionId);
    var cols = getGridColumns(actualViewMode, gridColumns);
    var posInSection = selectedFlatIndex - bounds.start;
    var newPosInSection = posInSection - cols;

    if (newPosInSection >= 0) {
        return bounds.start + newPosInSection;
    }

    var prevItem = findPrevNonHeaderIndex(flatModel, bounds.start - 1);
    return prevItem !== -1 ? prevItem : selectedFlatIndex;
}

function calculateRightIndex(flatModel, selectedFlatIndex, getSectionViewModeFn) {
    if (flatModel.length === 0)
        return selectedFlatIndex;

    var entry = flatModel[selectedFlatIndex];
    if (!entry || entry.isHeader) {
        var next = findNextNonHeaderIndex(flatModel, selectedFlatIndex + 1);
        return next !== -1 ? next : selectedFlatIndex;
    }

    var viewMode = getSectionViewModeFn(entry.sectionId);
    if (viewMode === "list") {
        var next = findNextNonHeaderIndex(flatModel, selectedFlatIndex + 1);
        return next !== -1 ? next : selectedFlatIndex;
    }

    var bounds = getSectionBounds(flatModel, entry.sectionId);
    var posInSection = selectedFlatIndex - bounds.start;
    if (posInSection + 1 < bounds.count) {
        return bounds.start + posInSection + 1;
    }
    return selectedFlatIndex;
}

function calculateLeftIndex(flatModel, selectedFlatIndex, getSectionViewModeFn) {
    if (flatModel.length === 0)
        return selectedFlatIndex;

    var entry = flatModel[selectedFlatIndex];
    if (!entry || entry.isHeader) {
        var prev = findPrevNonHeaderIndex(flatModel, selectedFlatIndex - 1);
        return prev !== -1 ? prev : selectedFlatIndex;
    }

    var viewMode = getSectionViewModeFn(entry.sectionId);
    if (viewMode === "list") {
        var prev = findPrevNonHeaderIndex(flatModel, selectedFlatIndex - 1);
        return prev !== -1 ? prev : selectedFlatIndex;
    }

    var bounds = getSectionBounds(flatModel, entry.sectionId);
    var posInSection = selectedFlatIndex - bounds.start;
    if (posInSection > 0) {
        return bounds.start + posInSection - 1;
    }
    return selectedFlatIndex;
}

function calculateNextSectionIndex(flatModel, selectedFlatIndex) {
    var currentSection = null;
    if (selectedFlatIndex >= 0 && selectedFlatIndex < flatModel.length) {
        currentSection = flatModel[selectedFlatIndex].sectionId;
    }

    var foundCurrent = false;
    for (var i = 0; i < flatModel.length; i++) {
        if (flatModel[i].isHeader) {
            if (foundCurrent) {
                for (var j = i + 1; j < flatModel.length; j++) {
                    if (!flatModel[j].isHeader)
                        return j;
                }
            }
            if (flatModel[i].section.id === currentSection) {
                foundCurrent = true;
            }
        }
    }
    return selectedFlatIndex;
}

function calculatePrevSectionIndex(flatModel, selectedFlatIndex) {
    var currentSection = null;
    if (selectedFlatIndex >= 0 && selectedFlatIndex < flatModel.length) {
        currentSection = flatModel[selectedFlatIndex].sectionId;
    }

    var lastSectionStart = -1;
    var prevSectionStart = -1;

    for (var i = 0; i < flatModel.length; i++) {
        if (flatModel[i].isHeader) {
            if (flatModel[i].section.id === currentSection) {
                break;
            }
            prevSectionStart = lastSectionStart;
            lastSectionStart = i;
        }
    }

    if (prevSectionStart >= 0) {
        for (var j = prevSectionStart + 1; j < flatModel.length; j++) {
            if (!flatModel[j].isHeader)
                return j;
        }
    }
    return selectedFlatIndex;
}

function calculatePageDownIndex(flatModel, selectedFlatIndex, visibleItems) {
    if (flatModel.length === 0)
        return selectedFlatIndex;

    var itemsToSkip = visibleItems || 8;
    var newIndex = selectedFlatIndex;

    for (var i = 0; i < itemsToSkip; i++) {
        var next = findNextNonHeaderIndex(flatModel, newIndex + 1);
        if (next === -1)
            break;
        newIndex = next;
    }

    return newIndex;
}

function calculatePageUpIndex(flatModel, selectedFlatIndex, visibleItems) {
    if (flatModel.length === 0)
        return selectedFlatIndex;

    var itemsToSkip = visibleItems || 8;
    var newIndex = selectedFlatIndex;

    for (var i = 0; i < itemsToSkip; i++) {
        var prev = findPrevNonHeaderIndex(flatModel, newIndex - 1);
        if (prev === -1)
            break;
        newIndex = prev;
    }

    return newIndex;
}
