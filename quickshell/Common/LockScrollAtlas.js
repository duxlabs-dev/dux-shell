.pragma library

function scrollWindow(imageWidth, imageHeight, screenWidth, screenHeight, scrollX, scrollY) {
    const scale = Math.max(screenWidth / imageWidth, screenHeight / imageHeight);
    const width = screenWidth / (imageWidth * scale);
    const height = screenHeight / (imageHeight * scale);
    const imageAspect = imageWidth / imageHeight;
    const screenAspect = screenWidth / screenHeight;
    return {
        x: imageAspect > screenAspect + 0.01 ? (1 - width) * scrollX / 100 : (1 - width) / 2,
        y: imageAspect < screenAspect - 0.01 ? (1 - height) * scrollY / 100 : (1 - height) / 2,
        width,
        height
    };
}

function atlasSize(imageWidth, imageHeight, screenWidth, screenHeight, sampleWidth, sampleHeight) {
    const view = scrollWindow(imageWidth, imageHeight, screenWidth, screenHeight, 0, 0);
    return {
        width: Math.ceil(sampleWidth / view.width),
        height: Math.ceil(sampleHeight / view.height)
    };
}

function crop(atlas, atlasWidth, atlasHeight, view, sampleWidth, sampleHeight) {
    const result = new Array(sampleWidth * sampleHeight);
    for (let y = 0; y < sampleHeight; y++) {
        const row = Math.min(atlasHeight - 1, Math.floor((view.y + (y + 0.5) / sampleHeight * view.height) * atlasHeight));
        for (let x = 0; x < sampleWidth; x++) {
            const column = Math.min(atlasWidth - 1, Math.floor((view.x + (x + 0.5) / sampleWidth * view.width) * atlasWidth));
            result[y * sampleWidth + x] = atlas[row * atlasWidth + column];
        }
    }
    return result;
}
