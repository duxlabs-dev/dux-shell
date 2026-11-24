.pragma library

var MAX_RATIO_DIFFERENCE = 1.5;
var MAX_UPSCALE = 1.5;

function closestVariant(item, display) {
    var distance = function (variant) {
        return Math.abs(Math.log(variant.width / variant.height * display.height / display.width));
    };
    return item.variants.reduce(function (best, variant) {
        return distance(variant) < distance(best) ? variant : best;
    });
}

// display is {width, height} in physical pixels.
function variantFor(item, display) {
    if (!item.variants || item.variants.length === 0 || !display)
        return item.path;
    return closestVariant(item, display).path;
}

// Unknown sizes pass.
function fits(item, display) {
    if (!display)
        return true;
    var size = item.variants && item.variants.length > 0 ? closestVariant(item, display) : item;
    if (!(size.width > 0) || !(size.height > 0))
        return true;
    var ratio = (size.width / size.height) / (display.width / display.height);
    if (Math.max(ratio, 1 / ratio) > MAX_RATIO_DIFFERENCE)
        return false;
    return Math.max(display.width / size.width, display.height / size.height) <= MAX_UPSCALE;
}
