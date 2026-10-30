package windowrules

import "github.com/duxlabs-dev/dux-shell/core/internal/configfrag"

type MatchCriteria struct {
	AppID              string `json:"appId,omitempty"`
	Title              string `json:"title,omitempty"`
	IsFloating         *bool  `json:"isFloating,omitempty"`
	IsActive           *bool  `json:"isActive,omitempty"`
	IsFocused          *bool  `json:"isFocused,omitempty"`
	IsActiveInColumn   *bool  `json:"isActiveInColumn,omitempty"`
	IsWindowCastTarget *bool  `json:"isWindowCastTarget,omitempty"`
	IsUrgent           *bool  `json:"isUrgent,omitempty"`
	AtStartup          *bool  `json:"atStartup,omitempty"`
	XWayland           *bool  `json:"xwayland,omitempty"`
	Fullscreen         *bool  `json:"fullscreen,omitempty"`
	Pinned             *bool  `json:"pinned,omitempty"`
	Initialised        *bool  `json:"initialised,omitempty"`

	InitialClass            string `json:"initialClass,omitempty"`
	InitialTitle            string `json:"initialTitle,omitempty"`
	Tag                     string `json:"tag,omitempty"`
	Workspace               string `json:"workspace,omitempty"`
	Content                 string `json:"content,omitempty"`
	XdgTag                  string `json:"xdgTag,omitempty"`
	Grouped                 *bool  `json:"group,omitempty"`
	Modal                   *bool  `json:"modal,omitempty"`
	FullscreenStateInternal *int   `json:"fullscreenStateInternal,omitempty"`
	FullscreenStateClient   *int   `json:"fullscreenStateClient,omitempty"`
}

type Actions struct {
	Opacity              *float64 `json:"opacity,omitempty"`
	OpenFloating         *bool    `json:"openFloating,omitempty"`
	OpenMaximized        *bool    `json:"openMaximized,omitempty"`
	OpenMaximizedToEdges *bool    `json:"openMaximizedToEdges,omitempty"`
	OpenFullscreen       *bool    `json:"openFullscreen,omitempty"`
	OpenFocused          *bool    `json:"openFocused,omitempty"`
	OpenOnOutput         string   `json:"openOnOutput,omitempty"`
	OpenOnWorkspace      string   `json:"openOnWorkspace,omitempty"`
	DefaultColumnWidth   string   `json:"defaultColumnWidth,omitempty"`
	DefaultWindowHeight  string   `json:"defaultWindowHeight,omitempty"`
	VariableRefreshRate  *bool    `json:"variableRefreshRate,omitempty"`
	BlockOutFrom         string   `json:"blockOutFrom,omitempty"`
	DefaultColumnDisplay string   `json:"defaultColumnDisplay,omitempty"`
	ScrollFactor         *float64 `json:"scrollFactor,omitempty"`
	CornerRadius         *int     `json:"cornerRadius,omitempty"`
	ClipToGeometry       *bool    `json:"clipToGeometry,omitempty"`
	TiledState           *bool    `json:"tiledState,omitempty"`
	MinWidth             *int     `json:"minWidth,omitempty"`
	MaxWidth             *int     `json:"maxWidth,omitempty"`
	MinHeight            *int     `json:"minHeight,omitempty"`
	MaxHeight            *int     `json:"maxHeight,omitempty"`
	BorderColor          string   `json:"borderColor,omitempty"`
	FocusRingColor       string   `json:"focusRingColor,omitempty"`
	FocusRingOff         *bool    `json:"focusRingOff,omitempty"`
	BorderOff            *bool    `json:"borderOff,omitempty"`
	DrawBorderWithBg     *bool    `json:"drawBorderWithBackground,omitempty"`
	BackgroundBlur       *bool    `json:"backgroundBlur,omitempty"`
	BackgroundXray       *bool    `json:"backgroundXray,omitempty"`
	BackgroundNoise      *float64 `json:"backgroundNoise,omitempty"`
	BackgroundSaturation *float64 `json:"backgroundSaturation,omitempty"`

	DefaultFloatingX          *int   `json:"defaultFloatingX,omitempty"`
	DefaultFloatingY          *int   `json:"defaultFloatingY,omitempty"`
	DefaultFloatingRelativeTo string `json:"defaultFloatingRelativeTo,omitempty"`
	MoveX                     string `json:"moveX,omitempty"`
	MoveY                     string `json:"moveY,omitempty"`
	SizeWidth                 string `json:"sizeWidth,omitempty"`
	SizeHeight                string `json:"sizeHeight,omitempty"`
	Monitor                   string `json:"monitor,omitempty"`
	Workspace                 string `json:"workspace,omitempty"`
	Tile                      *bool  `json:"tile,omitempty"`
	NoFocus                   *bool  `json:"nofocus,omitempty"`
	NoBorder                  *bool  `json:"noborder,omitempty"`
	NoShadow                  *bool  `json:"noshadow,omitempty"`
	NoDim                     *bool  `json:"nodim,omitempty"`
	NoBlur                    *bool  `json:"noblur,omitempty"`
	NoAnim                    *bool  `json:"noanim,omitempty"`
	NoRounding                *bool  `json:"norounding,omitempty"`
	Pin                       *bool  `json:"pin,omitempty"`
	Opaque                    *bool  `json:"opaque,omitempty"`
	ForcergbX                 *bool  `json:"forcergbx,omitempty"`
	Idleinhibit               string `json:"idleinhibit,omitempty"`

	NoInitialFocus  *bool    `json:"noInitialFocus,omitempty"`
	FocusOnActivate *bool    `json:"focusOnActivate,omitempty"`
	StayFocused     *bool    `json:"stayFocused,omitempty"`
	ConfinePointer  *bool    `json:"confinePointer,omitempty"`
	NoXdgDrags      *bool    `json:"noXdgDrags,omitempty"`
	NoAutoHDR       *bool    `json:"noAutoHdr,omitempty"`
	NoGlow          *bool    `json:"noGlow,omitempty"`
	NoWobble        *bool    `json:"noWobble,omitempty"`
	ScrollingWidth  *float64 `json:"scrollingWidth,omitempty"`
	Tonemap         string   `json:"tonemap,omitempty"`
	SuppressEvent   string   `json:"suppressEvent,omitempty"`
}

type WindowRule struct {
	ID            string          `json:"id"`
	Name          string          `json:"name,omitempty"`
	Enabled       bool            `json:"enabled"`
	MatchCriteria MatchCriteria   `json:"matchCriteria"`
	Matches       []MatchCriteria `json:"matches,omitempty"`
	Excludes      []MatchCriteria `json:"excludes,omitempty"`
	Actions       Actions         `json:"actions"`
	Source        string          `json:"source,omitempty"`
}

type DMSRulesStatus struct {
	Exists          bool   `json:"exists"`
	Included        bool   `json:"included"`
	IncludePosition int    `json:"includePosition"`
	TotalIncludes   int    `json:"totalIncludes"`
	RulesAfterDMS   int    `json:"rulesAfterDms"`
	Effective       bool   `json:"effective"`
	OverriddenBy    int    `json:"overriddenBy"`
	StatusMessage   string `json:"statusMessage"`
}

type RuleSet struct {
	Title            string          `json:"title"`
	Provider         string          `json:"provider"`
	Rules            []WindowRule    `json:"rules"`
	DMSRulesIncluded bool            `json:"dmsRulesIncluded"`
	DMSStatus        *DMSRulesStatus `json:"dmsStatus,omitempty"`
}

type Provider interface {
	Name() string
	GetRuleSet() (*RuleSet, error)
}

type WritableProvider interface {
	Provider
	SetRule(rule WindowRule) error
	RemoveRule(id string) error
	ReorderRules(ids []string) error
	GetOverridePath() string
}

func DMSRulesStatusFrom(s configfrag.Status) *DMSRulesStatus {
	return &DMSRulesStatus{
		Exists:          s.Exists,
		Included:        s.Included,
		IncludePosition: s.IncludePosition,
		TotalIncludes:   s.TotalIncludes,
		RulesAfterDMS:   s.EntriesAfterDMS,
		Effective:       s.Effective,
		OverriddenBy:    s.OverriddenBy,
		StatusMessage:   s.StatusMessage,
	}
}
