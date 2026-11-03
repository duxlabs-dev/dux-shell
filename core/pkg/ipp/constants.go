package ipp

// ipp status codes
const (
	StatusCupsInvalid                         int16 = -1
	StatusOk                                  int16 = 0x0000
	StatusOkIgnoredOrSubstituted              int16 = 0x0001
	StatusOkConflicting                       int16 = 0x0002
	StatusOkIgnoredSubscriptions              int16 = 0x0003
	StatusOkIgnoredNotifications              int16 = 0x0004
	StatusOkTooManyEvents                     int16 = 0x0005
	StatusOkButCancelSubscription             int16 = 0x0006
	StatusOkEventsComplete                    int16 = 0x0007
	StatusRedirectionOtherSite                int16 = 0x0200
	StatusCupsSeeOther                        int16 = 0x0280
	StatusErrorBadRequest                     int16 = 0x0400
	StatusErrorForbidden                      int16 = 0x0401
	StatusErrorNotAuthenticated               int16 = 0x0402
	StatusErrorNotAuthorized                  int16 = 0x0403
	StatusErrorNotPossible                    int16 = 0x0404
	StatusErrorTimeout                        int16 = 0x0405
	StatusErrorNotFound                       int16 = 0x0406
	StatusErrorGone                           int16 = 0x0407
	StatusErrorRequestEntity                  int16 = 0x0408
	StatusErrorRequestValue                   int16 = 0x0409
	StatusErrorDocumentFormatNotSupported     int16 = 0x040a
	StatusErrorAttributesOrValues             int16 = 0x040b
	StatusErrorUriScheme                      int16 = 0x040c
	StatusErrorCharset                        int16 = 0x040d
	StatusErrorConflicting                    int16 = 0x040e
	StatusErrorCompressionError               int16 = 0x040f
	StatusErrorDocumentFormatError            int16 = 0x0410
	StatusErrorDocumentAccess                 int16 = 0x0411
	StatusErrorAttributesNotSettable          int16 = 0x0412
	StatusErrorIgnoredAllSubscriptions        int16 = 0x0413
	StatusErrorTooManySubscriptions           int16 = 0x0414
	StatusErrorIgnoredAllNotifications        int16 = 0x0415
	StatusErrorPrintSupportFileNotFound       int16 = 0x0416
	StatusErrorDocumentPassword               int16 = 0x0417
	StatusErrorDocumentPermission             int16 = 0x0418
	StatusErrorDocumentSecurity               int16 = 0x0419
	StatusErrorDocumentUnprintable            int16 = 0x041a
	StatusErrorAccountInfoNeeded              int16 = 0x041b
	StatusErrorAccountClosed                  int16 = 0x041c
	StatusErrorAccountLimitReached            int16 = 0x041d
	StatusErrorAccountAuthorizationFailed     int16 = 0x041e
	StatusErrorNotFetchable                   int16 = 0x041f
	StatusErrorCupsAccountInfoNeeded          int16 = 0x049C
	StatusErrorCupsAccountClosed              int16 = 0x049d
	StatusErrorCupsAccountLimitReached        int16 = 0x049e
	StatusErrorCupsAccountAuthorizationFailed int16 = 0x049f
	StatusErrorInternal                       int16 = 0x0500
	StatusErrorOperationNotSupported          int16 = 0x0501
	StatusErrorServiceUnavailable             int16 = 0x0502
	StatusErrorVersionNotSupported            int16 = 0x0503
	StatusErrorDevice                         int16 = 0x0504
	StatusErrorTemporary                      int16 = 0x0505
	StatusErrorNotAcceptingJobs               int16 = 0x0506
	StatusErrorBusy                           int16 = 0x0507
	StatusErrorJobCanceled                    int16 = 0x0508
	StatusErrorMultipleJobsNotSupported       int16 = 0x0509
	StatusErrorPrinterIsDeactivated           int16 = 0x050a
	StatusErrorTooManyJobs                    int16 = 0x050b
	StatusErrorTooManyDocuments               int16 = 0x050c
	StatusErrorCupsAuthenticationCanceled     int16 = 0x1000
	StatusErrorCupsPki                        int16 = 0x1001
	StatusErrorCupsUpgradeRequired            int16 = 0x1002
)

// ipp operations
const (
	OperationCupsInvalid                     int16 = -0x0001
	OperationCupsNone                        int16 = 0x0000
	OperationPrintJob                        int16 = 0x0002
	OperationPrintUri                        int16 = 0x0003
	OperationValidateJob                     int16 = 0x0004
	OperationCreateJob                       int16 = 0x0005
	OperationSendDocument                    int16 = 0x0006
	OperationSendUri                         int16 = 0x0007
	OperationCancelJob                       int16 = 0x0008
	OperationGetJobAttributes                int16 = 0x0009
	OperationGetJobs                         int16 = 0x000a
	OperationGetPrinterAttributes            int16 = 0x000b
	OperationHoldJob                         int16 = 0x000c
	OperationReleaseJob                      int16 = 0x000d
	OperationRestartJob                      int16 = 0x000e
	OperationPausePrinter                    int16 = 0x0010
	OperationResumePrinter                   int16 = 0x0011
	OperationPurgeJobs                       int16 = 0x0012
	OperationSetPrinterAttributes            int16 = 0x0013
	OperationSetJobAttributes                int16 = 0x0014
	OperationGetPrinterSupportedValues       int16 = 0x0015
	OperationCreatePrinterSubscriptions      int16 = 0x0016
	OperationCreateJobSubscriptions          int16 = 0x0017
	OperationGetSubscriptionAttributes       int16 = 0x0018
	OperationGetSubscriptions                int16 = 0x0019
	OperationRenewSubscription               int16 = 0x001a
	OperationCancelSubscription              int16 = 0x001b
	OperationGetNotifications                int16 = 0x001c
	OperationSendNotifications               int16 = 0x001d
	OperationGetResourceAttributes           int16 = 0x001e
	OperationGetResourceData                 int16 = 0x001f
	OperationGetResources                    int16 = 0x0020
	OperationGetPrintSupportFiles            int16 = 0x0021
	OperationEnablePrinter                   int16 = 0x0022
	OperationDisablePrinter                  int16 = 0x0023
	OperationPausePrinterAfterCurrentJob     int16 = 0x0024
	OperationHoldNewJobs                     int16 = 0x0025
	OperationReleaseHeldNewJobs              int16 = 0x0026
	OperationDeactivatePrinter               int16 = 0x0027
	OperationActivatePrinter                 int16 = 0x0028
	OperationRestartPrinter                  int16 = 0x0029
	OperationShutdownPrinter                 int16 = 0x002a
	OperationStartupPrinter                  int16 = 0x002b
	OperationReprocessJob                    int16 = 0x002c
	OperationCancelCurrentJob                int16 = 0x002d
	OperationSuspendCurrentJob               int16 = 0x002e
	OperationResumeJob                       int16 = 0x002f
	OperationOperationPromoteJob             int16 = 0x0030
	OperationScheduleJobAfter                int16 = 0x0031
	OperationCancelDocument                  int16 = 0x0033
	OperationGetDocumentAttributes           int16 = 0x0034
	OperationGetDocuments                    int16 = 0x0035
	OperationDeleteDocument                  int16 = 0x0036
	OperationSetDocumentAttributes           int16 = 0x0037
	OperationCancelJobs                      int16 = 0x0038
	OperationCancelMyJobs                    int16 = 0x0039
	OperationResubmitJob                     int16 = 0x003a
	OperationCloseJob                        int16 = 0x003b
	OperationIdentifyPrinter                 int16 = 0x003c
	OperationValidateDocument                int16 = 0x003d
	OperationAddDocumentImages               int16 = 0x003e
	OperationAcknowledgeDocument             int16 = 0x003f
	OperationAcknowledgeIdentifyPrinter      int16 = 0x0040
	OperationAcknowledgeJob                  int16 = 0x0041
	OperationFetchDocument                   int16 = 0x0042
	OperationFetchJob                        int16 = 0x0043
	OperationGetOutputDeviceAttributes       int16 = 0x0044
	OperationUpdateActiveJobs                int16 = 0x0045
	OperationDeregisterOutputDevice          int16 = 0x0046
	OperationUpdateDocumentStatus            int16 = 0x0047
	OperationUpdateJobStatus                 int16 = 0x0048
	OperationUpdateOutputDeviceAttributes    int16 = 0x0049
	OperationGetNextDocumentData             int16 = 0x004a
	OperationAllocatePrinterResources        int16 = 0x004b
	OperationCreatePrinter                   int16 = 0x004c
	OperationDeallocatePrinterResources      int16 = 0x004d
	OperationDeletePrinter                   int16 = 0x004e
	OperationGetPrinters                     int16 = 0x004f
	OperationShutdownOnePrinter              int16 = 0x0050
	OperationStartupOnePrinter               int16 = 0x0051
	OperationCancelResource                  int16 = 0x0052
	OperationCreateResource                  int16 = 0x0053
	OperationInstallResource                 int16 = 0x0054
	OperationSendResourceData                int16 = 0x0055
	OperationSetResourceAttributes           int16 = 0x0056
	OperationCreateResourceSubscriptions     int16 = 0x0057
	OperationCreateSystemSubscriptions       int16 = 0x0058
	OperationDisableAllPrinters              int16 = 0x0059
	OperationEnableAllPrinters               int16 = 0x005a
	OperationGetSystemAttributes             int16 = 0x005b
	OperationGetSystemSupportedValues        int16 = 0x005c
	OperationPauseAllPrinters                int16 = 0x005d
	OperationPauseAllPrintersAfterCurrentJob int16 = 0x005e
	OperationRegisterOutputDevice            int16 = 0x005f
	OperationRestartSystem                   int16 = 0x0060
	OperationResumeAllPrinters               int16 = 0x0061
	OperationSetSystemAttributes             int16 = 0x0062
	OperationShutdownAllPrinter              int16 = 0x0063
	OperationStartupAllPrinters              int16 = 0x0064
	OperationPrivate                         int16 = 0x4000
	OperationCupsGetDefault                  int16 = 0x4001
	OperationCupsGetPrinters                 int16 = 0x4002
	OperationCupsAddModifyPrinter            int16 = 0x4003
	OperationCupsDeletePrinter               int16 = 0x4004
	OperationCupsGetClasses                  int16 = 0x4005
	OperationCupsAddModifyClass              int16 = 0x4006
	OperationCupsDeleteClass                 int16 = 0x4007
	OperationCupsAcceptJobs                  int16 = 0x4008
	OperationCupsRejectJobs                  int16 = 0x4009
	OperationCupsSetDefault                  int16 = 0x400a
	OperationCupsGetDevices                  int16 = 0x400b
	OperationCupsGetPPDs                     int16 = 0x400c
	OperationCupsMoveJob                     int16 = 0x400d
	OperationCupsAuthenticateJob             int16 = 0x400e
	OperationCupsGetPpd                      int16 = 0x400f
	OperationCupsGetDocument                 int16 = 0x4027
	OperationCupsCreateLocalPrinter          int16 = 0x4028
)

// ipp tags
const (
	TagCupsInvalid       int8 = -1
	TagZero              int8 = 0x00
	TagOperation         int8 = 0x01
	TagJob               int8 = 0x02
	TagEnd               int8 = 0x03
	TagPrinter           int8 = 0x04
	TagUnsupportedGroup  int8 = 0x05
	TagSubscription      int8 = 0x06
	TagEventNotification int8 = 0x07
	TagResource          int8 = 0x08
	TagDocument          int8 = 0x09
	TagSystem            int8 = 0x0a
	TagUnsupportedValue  int8 = 0x10
	TagDefault           int8 = 0x11
	TagUnknown           int8 = 0x12
	TagNoValue           int8 = 0x13
	TagNotSettable       int8 = 0x15
	TagDeleteAttr        int8 = 0x16
	TagAdminDefine       int8 = 0x17
	TagInteger           int8 = 0x21
	TagBoolean           int8 = 0x22
	TagEnum              int8 = 0x23
	TagString            int8 = 0x30
	TagDate              int8 = 0x31
	TagResolution        int8 = 0x32
	TagRange             int8 = 0x33
	TagBeginCollection   int8 = 0x34
	TagTextLang          int8 = 0x35
	TagNameLang          int8 = 0x36
	TagEndCollection     int8 = 0x37
	TagText              int8 = 0x41
	TagName              int8 = 0x42
	TagReservedString    int8 = 0x43
	TagKeyword           int8 = 0x44
	TagUri               int8 = 0x45
	TagUriScheme         int8 = 0x46
	TagCharset           int8 = 0x47
	TagLanguage          int8 = 0x48
	TagMimeType          int8 = 0x49
	TagMemberName        int8 = 0x4a
	TagExtension         int8 = 0x7f
)

// job states
const (
	JobStatePending    int8 = 0x03
	JobStateHeld       int8 = 0x04
	JobStateProcessing int8 = 0x05
	JobStateStopped    int8 = 0x06
	JobStateCanceled   int8 = 0x07
	JobStateAborted    int8 = 0x08
	JobStateCompleted  int8 = 0x09
)

// document states
const (
	DocumentStatePending    int8 = 0x03
	DocumentStateProcessing int8 = 0x05
	DocumentStateCanceled   int8 = 0x07
	DocumentStateAborted    int8 = 0x08
	DocumentStateCompleted  int8 = 0x08
)

// printer states
const (
	PrinterStateIdle       int8 = 0x0003
	PrinterStateProcessing int8 = 0x0004
	PrinterStateStopped    int8 = 0x0005
)

// job state filter
const (
	JobStateFilterNotCompleted = "not-completed"
	JobStateFilterCompleted    = "completed"
	JobStateFilterAll          = "all"
)

// error policies
const (
	ErrorPolicyRetryJob        = "retry-job"
	ErrorPolicyAbortJob        = "abort-job"
	ErrorPolicyRetryCurrentJob = "retry-current-job"
	ErrorPolicyStopPrinter     = "stop-printer"
)

// ipp defaults
const (
	// cups 2.4.20+ validates this case-sensitively (lowercase only), and libcups itself sends lowercase
	CharsetLanguage      = "en-us"
	Charset              = "utf-8"
	ProtocolVersionMajor = int8(2)
	ProtocolVersionMinor = int8(0)

	DefaultJobPriority = 50
)

// useful mime types for ipp
const (
	MimeTypePostscript  = "application/postscript"
	MimeTypePDF         = "application/pdf"
	MimeTypeOctetStream = "application/octet-stream"
)

// ipp content types
const (
	ContentTypeIPP = "application/ipp"
)

// known ipp attributes
const (
	AttributeCopies                  = "copies"
	AttributeDocumentFormat          = "document-format"
	AttributeDocumentName            = "document-name"
	AttributeJobID                   = "job-id"
	AttributeJobName                 = "job-name"
	AttributeJobPriority             = "job-priority"
	AttributeJobURI                  = "job-uri"
	AttributeLastDocument            = "last-document"
	AttributeMyJobs                  = "my-jobs"
	AttributePPDName                 = "ppd-name"
	AttributePPDMakeAndModel         = "ppd-make-and-model"
	AttributePrinterIsShared         = "printer-is-shared"
	AttributePrinterIsTemporary      = "printer-is-temporary"
	AttributePrinterURI              = "printer-uri"
	AttributePurgeJobs               = "purge-jobs"
	AttributeRequestedAttributes     = "requested-attributes"
	AttributeRequestingUserName      = "requesting-user-name"
	AttributeWhichJobs               = "which-jobs"
	AttributeFirstJobID              = "first-job-id"
	AttributeLimit                   = "limit"
	AttributeStatusMessage           = "status-message"
	AttributeCharset                 = "attributes-charset"
	AttributeNaturalLanguage         = "attributes-natural-language"
	AttributeDeviceURI               = "device-uri"
	AttributeHoldJobUntil            = "job-hold-until"
	AttributePrinterErrorPolicy      = "printer-error-policy"
	AttributePrinterInfo             = "printer-info"
	AttributePrinterLocation         = "printer-location"
	AttributePrinterName             = "printer-name"
	AttributePrinterStateReasons     = "printer-state-reasons"
	AttributeJobPrinterURI           = "job-printer-uri"
	AttributeMemberURIs              = "member-uris"
	AttributeDocumentNumber          = "document-number"
	AttributeDocumentState           = "document-state"
	AttributeFinishings              = "finishings"
	AttributeJobHoldUntil            = "hold-job-until"
	AttributeJobSheets               = "job-sheets"
	AttributeJobState                = "job-state"
	AttributeJobStateReason          = "job-state-reason"
	AttributeMedia                   = "media"
	AttributeSides                   = "sides"
	AttributeNumberUp                = "number-up"
	AttributeOrientationRequested    = "orientation-requested"
	AttributePrintQuality            = "print-quality"
	AttributePrinterIsAcceptingJobs  = "printer-is-accepting-jobs"
	AttributePrinterResolution       = "printer-resolution"
	AttributePrinterState            = "printer-state"
	AttributeMemberNames             = "member-names"
	AttributePrinterType             = "printer-type"
	AttributePrinterMakeAndModel     = "printer-make-and-model"
	AttributePrinterStateMessage     = "printer-state-message"
	AttributePrinterUriSupported     = "printer-uri-supported"
	AttributeJobMediaProgress        = "job-media-progress"
	AttributeJobKilobyteOctets       = "job-k-octets"
	AttributeNumberOfDocuments       = "number-of-documents"
	AttributeJobOriginatingUserName  = "job-originating-user-name"
	AttributeOutputOrder             = "outputorder"
	AttributeJobStateReasons         = "job-state-reasons"
	AttributeJobStateMessage         = "job-state-message"
	AttributeJobPrinterStateReasons  = "job-printer-state-reasons"
	AttributeJobPrinterStateMessage  = "job-printer-state-message"
	AttributeJobImpressionsCompleted = "job-impressions-completed"
	AttributePrintScaling            = "print-scaling"
)

// Default attributes
var (
	DefaultClassAttributes   = []string{AttributePrinterName, AttributeMemberNames}
	DefaultPrinterAttributes = []string{
		AttributePrinterName, AttributePrinterType, AttributePrinterLocation, AttributePrinterInfo,
		AttributePrinterMakeAndModel, AttributePrinterState, AttributePrinterStateMessage, AttributePrinterStateReasons,
		AttributePrinterUriSupported, AttributeDeviceURI, AttributePrinterIsShared,
	}
	DefaultJobAttributes = []string{
		AttributeJobID, AttributeJobName, AttributePrinterURI, AttributeJobState, AttributeJobStateReason,
		AttributeJobHoldUntil, AttributeJobMediaProgress, AttributeJobKilobyteOctets, AttributeNumberOfDocuments, AttributeCopies,
		AttributeJobOriginatingUserName,
	}
)

// Attribute to tag mapping
var (
	AttributeTagMapping = map[string]int8{
		AttributeCharset:                 TagCharset,
		AttributeNaturalLanguage:         TagLanguage,
		AttributeCopies:                  TagInteger,
		AttributeDeviceURI:               TagUri,
		AttributeDocumentFormat:          TagMimeType,
		AttributeDocumentName:            TagName,
		AttributeDocumentNumber:          TagInteger,
		AttributeDocumentState:           TagEnum,
		AttributeFinishings:              TagEnum,
		AttributeJobHoldUntil:            TagKeyword,
		AttributeHoldJobUntil:            TagKeyword,
		AttributeJobID:                   TagInteger,
		AttributeJobName:                 TagName,
		AttributeJobPrinterURI:           TagUri,
		AttributeJobPriority:             TagInteger,
		AttributeJobSheets:               TagName,
		AttributeJobState:                TagEnum,
		AttributeJobStateReason:          TagKeyword,
		AttributeJobURI:                  TagUri,
		AttributeLastDocument:            TagBoolean,
		AttributeMedia:                   TagKeyword,
		AttributeSides:                   TagKeyword,
		AttributeMemberURIs:              TagUri,
		AttributeMyJobs:                  TagBoolean,
		AttributeNumberUp:                TagInteger,
		AttributeOrientationRequested:    TagEnum,
		AttributePPDName:                 TagName,
		AttributePPDMakeAndModel:         TagText,
		AttributeNumberOfDocuments:       TagInteger,
		AttributePrintQuality:            TagEnum,
		AttributePrinterErrorPolicy:      TagName,
		AttributePrinterInfo:             TagText,
		AttributePrinterIsAcceptingJobs:  TagBoolean,
		AttributePrinterIsShared:         TagBoolean,
		AttributePrinterIsTemporary:      TagBoolean,
		AttributePrinterName:             TagName,
		AttributePrinterLocation:         TagText,
		AttributePrinterResolution:       TagResolution,
		AttributePrinterState:            TagEnum,
		AttributePrinterStateReasons:     TagKeyword,
		AttributePrinterURI:              TagUri,
		AttributePurgeJobs:               TagBoolean,
		AttributeRequestedAttributes:     TagKeyword,
		AttributeRequestingUserName:      TagName,
		AttributeWhichJobs:               TagKeyword,
		AttributeFirstJobID:              TagInteger,
		AttributeStatusMessage:           TagText,
		AttributeLimit:                   TagInteger,
		AttributeOutputOrder:             TagName,
		AttributeJobStateReasons:         TagString,
		AttributeJobStateMessage:         TagString,
		AttributeJobPrinterStateReasons:  TagString,
		AttributeJobPrinterStateMessage:  TagString,
		AttributeJobImpressionsCompleted: TagInteger,
		AttributePrintScaling:            TagKeyword,
		// IPP Subscription/Notification attributes (added for dankdots)
		"notify-events":           TagKeyword,
		"notify-pull-method":      TagKeyword,
		"notify-lease-duration":   TagInteger,
		"notify-subscription-id":  TagInteger,
		"notify-subscription-ids": TagInteger,
		"notify-sequence-numbers": TagInteger,
		"notify-wait":             TagBoolean,
		"notify-recipient-uri":    TagUri,
	}
)
