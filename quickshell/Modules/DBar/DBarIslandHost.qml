import QtQuick
import qs.Modules.DIsland

IslandBarHost {
    required property DBarBody body
    required property Item originItem
    required property Item slotLoader
    required property Item bandItem
    required property Item scrollItem

    barConfig: body.barConfig
    screen: body.screen
    hostWindow: body.hostWindow
    barId: body._barId
    originOffsetX: originItem.x + slotLoader.x
    originOffsetY: originItem.y + slotLoader.y
    hostOffsetX: body.hostOffsetX
    hostOffsetY: body.hostOffsetY
    chrome: body.islandChromeMode
    frameHosted: body.frameHosted
    slotItem: body.islandSlot
    barBody: body
    bandThickness: body.isVertical ? bandItem.width : bandItem.height
    bandInset: bandItem.spacingPx
    bandAlongStart: body.isVertical ? bandItem.y : bandItem.x
    bandAlongEnd: body.isVertical ? bandItem.y + bandItem.height : bandItem.x + bandItem.width
    bandColor: body._bgColor
    leadingSectionRect: body.leadingSectionRect
    centerSectionRect: body.centerSectionRect
    trailingSectionRect: body.trailingSectionRect
    onScrollWheel: wheel => scrollItem.processWheel(wheel)
}
