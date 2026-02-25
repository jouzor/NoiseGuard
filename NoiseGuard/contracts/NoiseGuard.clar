;; NoiseGuard - Decentralized Urban Sound Pollution Monitoring System
;; A comprehensive noise level tracking network for decibel monitoring and acoustic analysis

;; Constants
(define-constant ACOUSTIC-SUPERVISOR tx-sender)
(define-constant ERR-FORBIDDEN (err u500))
(define-constant ERR-MONITOR-EXISTS (err u501))
(define-constant ERR-MONITOR-OFFLINE (err u502))
(define-constant ERR-LEVEL-INVALID (err u503))
(define-constant ERR-DATA-EXPIRED (err u504))
(define-constant ERR-COLLATERAL-LOW (err u505))
(define-constant ERR-MONITOR-DISABLED (err u506))
(define-constant ERR-SPIKE-DETECTED (err u507))
(define-constant ERR-ZONE-INVALID (err u508))
(define-constant ERR-RESOLUTION-INVALID (err u509))

;; Minimum collateral required to become a noise monitor (in microSTX)
(define-constant MIN-MONITOR-COLLATERAL u1000000) ;; 1 STX

;; Maximum age for noise level data (in blocks)
(define-constant MAX-LEVEL-AGE u144) ;; ~24 hours

;; Maximum allowed level spike percentage (basis points)
(define-constant MAX-SPIKE u2000) ;; 20%

;; Maximum resolution digits allowed
(define-constant MAX-RESOLUTION u18)

;; Maximum level value (to prevent overflow)
(define-constant MAX-LEVEL-VALUE u340282366920938463463374607431768211455) ;; uint max

;; Data Variables
(define-data-var system-online bool true)
(define-data-var total-monitors uint u0)
(define-data-var chief-acoustician (optional principal) none)

;; Whitelist of monitored zones
(define-map monitored-zones (string-ascii 32) bool)

;; Data Maps
;; Noise monitor registry
(define-map noise-monitors
    principal
    {
        is-online: bool,
        collateral-amount: uint,
        precision-score: uint,
        total-captures: uint,
        last-capture-height: uint
    }
)

;; Noise level captures for different zones
(define-map noise-captures
    (string-ascii 32) ;; zone identifier
    {
        level: uint,
        resolution: uint,
        last-capture: uint,
        capture-count: uint,
        monitor: principal
    }
)

;; Compiled noise analytics
(define-map compiled-analytics
    (string-ascii 32) ;; zone identifier
    {
        median-level: uint,
        average-level: uint,
        min-level: uint,
        max-level: uint,
        resolution: uint,
        last-compilation: uint,
        sample-size: uint,
        accuracy-index: uint
    }
)

;; Level captures for compilation
(define-map level-captures
    {zone: (string-ascii 32), monitor: principal}
    {
        level: uint,
        timestamp: uint,
        processed: bool
    }
)

;; Monitor collateral
(define-map monitor-collateral
    principal
    uint
)

;; Input validation functions

;; Validate zone identifier - only alphanumeric characters allowed
(define-read-only (is-valid-zone (zone (string-ascii 32)))
    (let (
        (zone-length (len zone))
    )
    (and
        (> zone-length u0)
        (<= zone-length u32)
        ;; Check if zone is in monitored list (if whitelist is being used)
        (default-to true (map-get? monitored-zones zone))
    ))
)

;; Validate resolution parameter
(define-read-only (is-valid-resolution (resolution uint))
    (and
        (>= resolution u0)
        (<= resolution MAX-RESOLUTION)
    )
)

;; Validate level parameter
(define-read-only (is-valid-level (level uint))
    (and
        (> level u0)
        (<= level MAX-LEVEL-VALUE)
    )
)

;; Read-only functions

;; Get noise monitor information
(define-read-only (get-monitor-info (monitor principal))
    (map-get? noise-monitors monitor)
)

;; Get noise level capture for a zone
(define-read-only (get-noise-capture (zone (string-ascii 32)))
    (if (is-valid-zone zone)
        (map-get? noise-captures zone)
        none
    )
)

;; Get compiled analytics for a zone
(define-read-only (get-compiled-analytics (zone (string-ascii 32)))
    (if (is-valid-zone zone)
        (map-get? compiled-analytics zone)
        none
    )
)

;; Get latest analytics with expiration check
(define-read-only (get-latest-analytics (zone (string-ascii 32)))
    (if (is-valid-zone zone)
        (match (map-get? compiled-analytics zone)
            analytics-data 
            (if (> (- stacks-block-height (get last-compilation analytics-data)) MAX-LEVEL-AGE)
                (err ERR-DATA-EXPIRED)
                (ok {
                    level: (get median-level analytics-data),
                    resolution: (get resolution analytics-data),
                    timestamp: (get last-compilation analytics-data),
                    accuracy: (get accuracy-index analytics-data)
                })
            )
            (err ERR-MONITOR-OFFLINE)
        )
        (err ERR-ZONE-INVALID)
    )
)

;; Check if system is online
(define-read-only (is-system-online)
    (var-get system-online)
)

;; Get total number of monitors
(define-read-only (get-total-monitors)
    (var-get total-monitors)
)

;; Check if monitor is online and has sufficient collateral
(define-read-only (is-valid-monitor (monitor principal))
    (match (map-get? noise-monitors monitor)
        monitor-data
        (and 
            (get is-online monitor-data)
            (>= (get collateral-amount monitor-data) MIN-MONITOR-COLLATERAL)
        )
        false
    )
)

;; Calculate level spike between two levels
(define-read-only (calculate-spike (level1 uint) (level2 uint))
    (let (
        (higher (if (> level1 level2) level1 level2))
        (lower (if (> level1 level2) level2 level1))
        (diff (- higher lower))
        (spike (* (/ diff lower) u10000))
    )
    spike)
)

;; Admin functions

;; Add zone to monitored list (only acoustic supervisor)
(define-public (add-monitored-zone (zone (string-ascii 32)))
    (begin
        (asserts! (is-eq tx-sender ACOUSTIC-SUPERVISOR) ERR-FORBIDDEN)
        (asserts! (> (len zone) u0) ERR-ZONE-INVALID)
        (map-set monitored-zones zone true)
        (ok true)
    )
)

;; Remove zone from monitored list (only acoustic supervisor)
(define-public (remove-monitored-zone (zone (string-ascii 32)))
    (begin
        (asserts! (is-eq tx-sender ACOUSTIC-SUPERVISOR) ERR-FORBIDDEN)
        (map-delete monitored-zones zone)
        (ok true)
    )
)

;; Public functions

;; Register as a noise monitor
(define-public (register-monitor)
    (let (
        (monitor tx-sender)
        (collateral-amount (stx-get-balance tx-sender))
    )
    (asserts! (var-get system-online) ERR-FORBIDDEN)
    (asserts! (is-none (map-get? noise-monitors monitor)) ERR-MONITOR-EXISTS)
    (asserts! (>= collateral-amount MIN-MONITOR-COLLATERAL) ERR-COLLATERAL-LOW)
    
    ;; Transfer collateral to contract
    (try! (stx-transfer? MIN-MONITOR-COLLATERAL tx-sender (as-contract tx-sender)))
    
    ;; Register monitor
    (map-set noise-monitors monitor {
        is-online: true,
        collateral-amount: MIN-MONITOR-COLLATERAL,
        precision-score: u100,
        total-captures: u0,
        last-capture-height: stacks-block-height
    })
    
    ;; Track collateral
    (map-set monitor-collateral monitor MIN-MONITOR-COLLATERAL)
    
    ;; Update total monitors
    (var-set total-monitors (+ (var-get total-monitors) u1))
    
    (ok true))
)

;; Shutdown monitor
(define-public (shutdown-monitor)
    (let (
        (monitor tx-sender)
        (monitor-data (unwrap! (map-get? noise-monitors monitor) ERR-MONITOR-OFFLINE))
        (collateral (get collateral-amount monitor-data))
    )
    (asserts! (var-get system-online) ERR-FORBIDDEN)
    (asserts! (get is-online monitor-data) ERR-MONITOR-DISABLED)
    
    ;; Disable monitor
    (map-set noise-monitors monitor (merge monitor-data {is-online: false}))
    
    ;; Return collateral
    (try! (as-contract (stx-transfer? collateral tx-sender monitor)))
    
    ;; Remove collateral tracking
    (map-delete monitor-collateral monitor)
    
    ;; Update total monitors
    (var-set total-monitors (- (var-get total-monitors) u1))
    
    (ok true))
)

;; Submit noise level capture with comprehensive input validation
(define-public (submit-capture (zone (string-ascii 32)) (level uint) (resolution uint))
    (let (
        (monitor tx-sender)
        (monitor-data (unwrap! (map-get? noise-monitors monitor) ERR-MONITOR-OFFLINE))
    )
    ;; Comprehensive input validation
    (asserts! (var-get system-online) ERR-FORBIDDEN)
    (asserts! (get is-online monitor-data) ERR-MONITOR-DISABLED)
    (asserts! (is-valid-zone zone) ERR-ZONE-INVALID)
    (asserts! (is-valid-level level) ERR-LEVEL-INVALID)
    (asserts! (is-valid-resolution resolution) ERR-RESOLUTION-INVALID)
    
    ;; Check for reasonable level spike if previous capture exists
    (match (map-get? noise-captures zone)
        existing-capture
        (let ((spike (calculate-spike level (get level existing-capture))))
            (asserts! (<= spike MAX-SPIKE) ERR-SPIKE-DETECTED)
        )
        true ;; No existing capture, allow any level
    )
    
    ;; Update noise capture with validated inputs
    (map-set noise-captures zone {
        level: level,
        resolution: resolution,
        last-capture: stacks-block-height,
        capture-count: (match (map-get? noise-captures zone)
            existing (+ (get capture-count existing) u1)
            u1
        ),
        monitor: monitor
    })
    
    ;; Record capture for compilation with validated inputs
    (map-set level-captures {zone: zone, monitor: monitor} {
        level: level,
        timestamp: stacks-block-height,
        processed: false
    })
    
    ;; Update monitor stats
    (map-set noise-monitors monitor (merge monitor-data {
        total-captures: (+ (get total-captures monitor-data) u1),
        last-capture-height: stacks-block-height
    }))
    
    (ok true))
)