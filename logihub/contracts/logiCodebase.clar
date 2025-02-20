;; Supply Chain Quality Control Smart Contract 
;; Complete system with performance tracking and advanced quality control

;; Error codes
(define-constant ACCESS_FORBIDDEN (err u100))
(define-constant DUPLICATE_ENTRY_ERROR (err u101))
(define-constant ENTRY_MISSING_ERROR (err u102))
(define-constant OPERATION_BLOCKED_ERROR (err u103))
(define-constant DEPOSIT_MISSING_ERROR (err u104))
(define-constant TIME_RESTRICTION_ERROR (err u105))
(define-constant LIMIT_BREACH_ERROR (err u106))
(define-constant TEMPORAL_ERROR (err u107))
(define-constant INVALID_PRODUCT_IDENTIFIER (err u400))
(define-constant INVALID_QUALITY_CERTIFICATION (err u401))
(define-constant INVALID_DEFECT_DOCUMENTATION (err u402))
(define-constant INVALID_DEFECT_SEVERITY (err u403))
(define-constant INVALID_QUALITY_LEVEL (err u404))
(define-constant INVALID_MANAGER_ADDRESS (err u405))

;; System constants
(define-constant REVIEW_WINDOW u86400) ;; 24 hours in seconds
(define-constant BASE_DEPOSIT_REQUIREMENT u1000000) ;; in microSTX
(define-constant RELIABILITY_BASELINE u50)
(define-constant DOCUMENTATION_STRING_LIMIT u500)

;; Input validation functions
(define-private (validate-product-identifier (product_id (string-ascii 255)))
    (begin
        (asserts! (>= (len product_id) u3) (err "Product ID too short"))
        (asserts! (<= (len product_id) u255) (err "Product ID too long"))
        (asserts! (is-eq (index-of product_id ".") none) (err "Invalid character: ."))
        (asserts! (is-eq (index-of product_id "/") none) (err "Invalid character: /"))
        (asserts! (is-eq (index-of product_id " ") none) (err "Invalid character: space"))
        (ok true)))

(define-private (validate-quality-certification (certification (string-ascii 50)))
    (begin
        (asserts! (>= (len certification) u5) (err "Certification too short"))
        (asserts! (<= (len certification) u50) (err "Certification too long"))
        (asserts! (is-eq (index-of certification "<") none) (err "Invalid character: <"))
        (asserts! (is-eq (index-of certification ">") none) (err "Invalid character: >"))
        (ok true)))

(define-private (validate-defect-documentation (documentation (string-ascii 500)))
    (begin
        (asserts! (>= (len documentation) u10) (err "Defect documentation too short"))
        (asserts! (<= (len documentation) u500) (err "Defect documentation too long"))
        (asserts! (is-eq (index-of documentation "<") none) (err "Invalid character: <"))
        (asserts! (is-eq (index-of documentation ">") none) (err "Invalid character: >"))
        (ok true)))

(define-private (validate-defect-severity (severity uint))
    (begin
        (asserts! (>= severity u1) (err "Defect severity too low"))
        (asserts! (<= severity u100) (err "Defect severity too high"))
        (ok true)))

(define-private (validate-quality-level (level uint))
    (begin
        (asserts! (>= level u1) (err "Quality level too low"))
        (asserts! (<= level u10) (err "Quality level too high"))
        (ok true)))

;; Administrative state variables
(define-data-var quality_manager principal tx-sender)
(define-data-var inspection_cost uint u100)
(define-data-var defect_confirmation_minimum uint u5)
(define-data-var quality_control_intensity uint u1)
(define-data-var system_pause_state bool false)

;; Primary data structures
(define-map registered_products
    {product_identifier: (string-ascii 255)}
    {
        manufacturer: principal,
        quality_level: (string-ascii 20),
        registration_epoch: uint,
        defect_metric: uint,
        defect_count: uint,
        locked_deposit: uint,
        inspection_epoch: uint,
        quality_certification: (string-ascii 50)
    })

(define-map defective_product_registry
    {product_identifier: (string-ascii 255)}
    {
        reporting_inspector: principal,
        detection_epoch: uint,
        defect_documentation: (string-ascii 500),
        verification_state: (string-ascii 20),
        defect_severity: uint,
        affected_units: uint
    })

(define-map inspector_performance_log
    {inspector_id: principal, target_product: (string-ascii 255)}
    {
        report_count: uint,
        last_action_epoch: uint,
        reliability_score: uint,
        reserved_funds: uint,
        verified_reports: uint
    })

(define-map product_inspection_records
    {product_identifier: (string-ascii 255)}
    {
        inspection_frequency: uint,
        recent_check_epoch: uint,
        inspector_id: principal,
        quality_rating: uint,
        compliance_status: (string-ascii 50)
    })

(define-map inspector_registry
    {inspector_id: principal}
    {
        reserved_amount: uint,
        inspection_count: uint,
        accuracy_metric: uint,
        recent_activity_epoch: uint,
        operational_status: (string-ascii 20)
    })

;; Query functions
(define-read-only (fetch_product_status (product_identifier (string-ascii 255)))
    (match (map-get? registered_products {product_identifier: product_identifier})
        some_entry (ok some_entry)
        (err ENTRY_MISSING_ERROR)))

(define-read-only (check_defect_status (product_identifier (string-ascii 255)))
    (is-some (map-get? defective_product_registry {product_identifier: product_identifier})))

(define-read-only (fetch_inspector_rating (inspector_id principal))
    (match (map-get? inspector_performance_log {inspector_id: inspector_id, target_product: ""})
        some_data (get reliability_score some_data)
        u0))

;; Core operations
(define-public (register_product 
    (product_identifier (string-ascii 255))
    (quality_certification (string-ascii 50)))
    (let (
        (current_epoch (unwrap-panic (get-block-info? time (- block-height u1))))
        (deposit_requirement (* BASE_DEPOSIT_REQUIREMENT (var-get quality_control_intensity))))
        
        (asserts! (is-ok (validate-product-identifier product_identifier)) INVALID_PRODUCT_IDENTIFIER)
        (asserts! (is-ok (validate-quality-certification quality_certification)) INVALID_QUALITY_CERTIFICATION)
        (asserts! (is-eq tx-sender (var-get quality_manager)) ACCESS_FORBIDDEN)
        (asserts! (>= (stx-get-balance tx-sender) deposit_requirement) DEPOSIT_MISSING_ERROR)
        
        (match (map-get? registered_products {product_identifier: product_identifier})
            some_entry DUPLICATE_ENTRY_ERROR
            (begin
                (try! (stx-transfer? deposit_requirement tx-sender (as-contract tx-sender)))
                (map-set registered_products
                    {product_identifier: product_identifier}
                    {
                        manufacturer: tx-sender,
                        quality_level: "certified",
                        registration_epoch: current_epoch,
                        defect_metric: u0,
                        defect_count: u0,
                        locked_deposit: deposit_requirement,
                        inspection_epoch: current_epoch,
                        quality_certification: quality_certification
                    })
                (ok true)))))

(define-public (report_defect 
    (product_identifier (string-ascii 255)) 
    (defect_documentation (string-ascii 500))
    (defect_severity uint))
    (let (
        (current_epoch (unwrap-panic (get-block-info? time (- block-height u1))))
        (inspector_data (default-to 
            {report_count: u0, last_action_epoch: u0, reliability_score: u0, reserved_funds: u0, verified_reports: u0}
            (map-get? inspector_performance_log {inspector_id: tx-sender, target_product: product_identifier}))))
        
        (asserts! (is-ok (validate-product-identifier product_identifier)) INVALID_PRODUCT_IDENTIFIER)
        (asserts! (is-ok (validate-defect-documentation defect_documentation)) INVALID_DEFECT_DOCUMENTATION)
        (asserts! (is-ok (validate-defect-severity defect_severity)) INVALID_DEFECT_SEVERITY)
        (asserts! (not (var-get system_pause_state)) OPERATION_BLOCKED_ERROR)
        (asserts! (>= (get reliability_score inspector_data) RELIABILITY_BASELINE) DEPOSIT_MISSING_ERROR)
        (asserts! (> (- current_epoch (get last_action_epoch inspector_data)) REVIEW_WINDOW) TIME_RESTRICTION_ERROR)
        
        (map-set defective_product_registry
            {product_identifier: product_identifier}
            {
                reporting_inspector: tx-sender,
                detection_epoch: current_epoch,
                defect_documentation: defect_documentation,
                verification_state: "pending",
                defect_severity: defect_severity,
                affected_units: u1
            })
        
        (map-set inspector_performance_log
            {inspector_id: tx-sender, target_product: product_identifier}
            {
                report_count: (+ (get report_count inspector_data) u1),
                last_action_epoch: current_epoch,
                reliability_score: (+ (get reliability_score inspector_data) u5),
                reserved_funds: (get reserved_funds inspector_data),
                verified_reports: (get verified_reports inspector_data)
            })
        (ok true)))

(define-private (modify_product_risk (product_identifier (string-ascii 255)) (adjustment_value int))
    (begin 
        (asserts! (is-ok (validate-product-identifier product_identifier)) INVALID_PRODUCT_IDENTIFIER)
        (match (map-get? registered_products {product_identifier: product_identifier})
            some_entry 
                (begin
                    (map-set registered_products
                        {product_identifier: product_identifier}
                        (merge some_entry {
                            defect_metric: (+ (get defect_metric some_entry) 
                                (if (> adjustment_value 0) 
                                    (to-uint adjustment_value)
                                    u0))
                        }))
                    (ok true))
            ENTRY_MISSING_ERROR)))

(define-public (validate_defect_report 
    (product_identifier (string-ascii 255))
    (is_valid bool))
    (let (
        (current_epoch (unwrap-panic (get-block-info? time (- block-height u1))))
        (inspector_status (unwrap! (map-get? inspector_registry {inspector_id: tx-sender}) ACCESS_FORBIDDEN)))
        
        (asserts! (is-ok (validate-product-identifier product_identifier)) INVALID_PRODUCT_IDENTIFIER)
        (asserts! (>= (get reserved_amount inspector_status) BASE_DEPOSIT_REQUIREMENT) DEPOSIT_MISSING_ERROR)
        
        (map-set inspector_registry
            {inspector_id: tx-sender}
            (merge inspector_status {
                inspection_count: (+ (get inspection_count inspector_status) u1),
                recent_activity_epoch: current_epoch
            }))
        (if is_valid
            (modify_product_risk product_identifier 10)
            (modify_product_risk product_identifier -5))))

(define-public (register_inspector (deposit_amount uint))
    (let (
        (current_epoch (unwrap-panic (get-block-info? time (- block-height u1)))))
        (asserts! (>= deposit_amount BASE_DEPOSIT_REQUIREMENT) DEPOSIT_MISSING_ERROR)
        (asserts! (>= (stx-get-balance tx-sender) deposit_amount) DEPOSIT_MISSING_ERROR)
        
        (map-set inspector_registry
            {inspector_id: tx-sender}
            {
                reserved_amount: deposit_amount,
                inspection_count: u0,
                accuracy_metric: u100,
                recent_activity_epoch: current_epoch,
                operational_status: "active"
            })
        (unwrap! (stx-transfer? deposit_amount tx-sender (as-contract tx-sender))
                 DEPOSIT_MISSING_ERROR)
        (ok true)))

;; System management functions
(define-public (modify_quality_level (new_level uint))
    (begin
        (asserts! (is-ok (validate-quality-level new_level)) INVALID_QUALITY_LEVEL)
        (asserts! (is-eq tx-sender (var-get quality_manager)) ACCESS_FORBIDDEN)
        (var-set quality_control_intensity new_level)
        (ok true)))

(define-public (toggle_system_state (pause_state bool))
    (begin
        (asserts! (is-eq tx-sender (var-get quality_manager)) ACCESS_FORBIDDEN)
        (var-set system_pause_state pause_state)
        (ok true)))

(define-public (reassign_quality_manager (new_manager principal))
    (begin
        (asserts! (is-eq tx-sender (var-get quality_manager)) ACCESS_FORBIDDEN)
        (asserts! (not (is-eq new_manager 'SP000000000000000000002Q6VF78)) INVALID_MANAGER_ADDRESS)
        (var-set quality_manager new_manager)
        (ok true)))

;; System initialization
(define-public (initialize_system (admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get quality_manager)) ACCESS_FORBIDDEN)
        (asserts! (not (is-eq admin 'SP000000000000000000002Q6VF78)) INVALID_MANAGER_ADDRESS)
        (var-set quality_manager admin)
        (var-set quality_control_intensity u1)
        (var-set system_pause_state false)
        (ok true)))