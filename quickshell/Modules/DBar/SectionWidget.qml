import qs.Modules.SurfaceWidgets

SurfaceWidgetHost {
    required property var sectionContext

    surfaceContext: sectionContext.surfaceContext
    widgetId: widgetData.widgetId
    spacerSize: widgetData.size || 20
    components: sectionContext.components
    isInColumn: sectionContext.isVertical
    axis: sectionContext.axis
    section: sectionContext.section
    parentScreen: sectionContext.parentScreen
    widgetThickness: sectionContext.widgetThickness
    barThickness: sectionContext.barThickness
    barSpacing: sectionContext.barSpacing
    barConfig: sectionContext.barConfig
    blurBarWindow: sectionContext.blurBarWindow
    sectionAvailablePrimarySize: sectionContext.sectionAvailablePrimarySize
    sectionSpacing: sectionContext.widgetSpacing
    segmentRole: sectionContext.roleAt(occurrenceOrder)
    isLeftBarEdge: !isInColumn && section === "left" && sectionContext.edgeIsScreenEdge
    isRightBarEdge: !isInColumn && section === "right" && sectionContext.edgeIsScreenEdge
    isTopBarEdge: isInColumn && section === "left" && sectionContext.edgeIsScreenEdge
    isBottomBarEdge: isInColumn && section === "right" && sectionContext.edgeIsScreenEdge
    crossEdgeExtension: !isInColumn && section !== "center" ? sectionContext.crossEdgeExtension : 0
}
