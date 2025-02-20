;; Supply Chain Quality Control Smart Contract - v1
;; Basic product registration and quality tracking

;; Error codes
(define-constant ACCESS_FORBIDDEN (err u100))
(define-constant DUPLICATE_ENTRY_ERROR (err u101))
(define-constant ENTRY_MISSING_ERROR (err u102))
(define-constant DEPOSIT_MISSING_ERROR (err u104))
(define-constant INVALID_PRODUCT_IDENTIFIER (err u400))
(define-constant INVALID_QUALITY_CERTIFICATION (err u401))
(define-constant INVALID_MANAGER_ADDRESS (err u405))

;; System constants
(define-constant BASE_DEPOSIT_REQUIREMENT u1000000) ;; in microSTX

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

;; Administrative state variables
(define-data-var quality_manager principal tx-sender)

;; Primary data structures
(define-map registered_products
    {product_identifier: (string-ascii 255)}
    {
        manufacturer: principal,
        quality_level: (string-ascii 20),
        registration_epoch: uint,
        locked_deposit: uint,
        quality_certification: (string-ascii 50)
    })

;; Query functions
(define-read-only (fetch_product_status (product_identifier (string-ascii 255)))
    (match (map-get? registered_products {product_identifier: product_identifier})
        some_entry (ok some_entry)
        (err ENTRY_MISSING_ERROR)))

;; Core operations
(define-public (register_product 
    (product_identifier (string-ascii 255))
    (quality_certification (string-ascii 50)))
    (let (
        (current_epoch (unwrap-panic (get-block-info? time (- block-height u1)))))
        
        (asserts! (is-ok (validate-product-identifier product_identifier)) INVALID_PRODUCT_IDENTIFIER)
        (asserts! (is-ok (validate-quality-certification quality_certification)) INVALID_QUALITY_CERTIFICATION)
        (asserts! (is-eq tx-sender (var-get quality_manager)) ACCESS_FORBIDDEN)
        (asserts! (>= (stx-get-balance tx-sender) BASE_DEPOSIT_REQUIREMENT) DEPOSIT_MISSING_ERROR)
        
        (match (map-get? registered_products {product_identifier: product_identifier})
            some_entry DUPLICATE_ENTRY_ERROR
            (begin
                (try! (stx-transfer? BASE_DEPOSIT_REQUIREMENT tx-sender (as-contract tx-sender)))
                (map-set registered_products
                    {product_identifier: product_identifier}
                    {
                        manufacturer: tx-sender,
                        quality_level: "certified",
                        registration_epoch: current_epoch,
                        locked_deposit: BASE_DEPOSIT_REQUIREMENT,
                        quality_certification: quality_certification
                    })
                (ok true)))))

;; System initialization
(define-public (initialize_system (admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get quality_manager)) ACCESS_FORBIDDEN)
        (asserts! (not (is-eq admin 'SP000000000000000000002Q6VF78)) INVALID_MANAGER_ADDRESS)
        (var-set quality_manager admin)
        (ok true)))