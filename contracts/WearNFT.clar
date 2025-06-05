(define-read-only (contract-version)
    (ok "WearNFT v1.0.0")
)
(define-read-only (contract-name)
    (ok "WearNFT Marketplace")
)
(define-non-fungible-token wear-nft uint)

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-listing-not-found (err u102))
(define-constant err-insufficient-funds (err u103))
(define-constant err-token-not-found (err u104))
(define-constant err-already-minted (err u105))
(define-constant err-invalid-price (err u106))

(define-data-var last-token-id uint u0)
(define-data-var contract-uri (string-ascii 256) "")

(define-map token-metadata uint {
    name: (string-ascii 64),
    description: (string-ascii 256),
    image: (string-ascii 256),
    product-type: (string-ascii 32),
    size: (string-ascii 8),
    color: (string-ascii 16),
    physical-shipped: bool,
    tracking-number: (optional (string-ascii 64))
})

(define-map marketplace-listings uint {
    seller: principal,
    price: uint,
    active: bool
})

(define-map product-templates (string-ascii 64) {
    base-price: uint,
    available-sizes: (list 10 (string-ascii 8)),
    available-colors: (list 10 (string-ascii 16)),
    max-supply: uint,
    current-supply: uint
})

(define-map user-orders principal (list 50 uint))

(define-public (initialize-contract (uri (string-ascii 256)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set contract-uri uri)
        (ok true)
    )
)

(define-public (add-product-template 
    (template-name (string-ascii 64))
    (base-price uint)
    (sizes (list 10 (string-ascii 8)))
    (colors (list 10 (string-ascii 16)))
    (max-supply uint)
)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> base-price u0) err-invalid-price)
        (map-set product-templates template-name {
            base-price: base-price,
            available-sizes: sizes,
            available-colors: colors,
            max-supply: max-supply,
            current-supply: u0
        })
        (ok true)
    )
)

(define-public (mint-nft 
    (recipient principal)
    (template-name (string-ascii 64))
    (product-name (string-ascii 64))
    (description (string-ascii 256))
    (image (string-ascii 256))
    (size (string-ascii 8))
    (color (string-ascii 16))
)
    (let (
        (token-id (+ (var-get last-token-id) u1))
        (template (unwrap! (map-get? product-templates template-name) err-not-token-owner))
    )
        (begin
            (asserts! (is-eq tx-sender contract-owner) err-owner-only)
            (asserts! (< (get current-supply template) (get max-supply template)) err-already-minted)
            (try! (nft-mint? wear-nft token-id recipient))
            (map-set token-metadata token-id {
                name: product-name,
                description: description,
                image: image,
                product-type: (unwrap-panic (as-max-len? (unwrap-panic (slice? template-name u0 u32)) u32)),
                size: size,
                color: color,
                physical-shipped: false,
                tracking-number: none
            })
            (map-set product-templates template-name 
                (merge template { current-supply: (+ (get current-supply template) u1) })
            )
            (var-set last-token-id token-id)
            (ok token-id)
        )
    )
)
(define-public (purchase-nft 
    (template-name (string-ascii 64))
    (size (string-ascii 8))
    (color (string-ascii 16))
)
    (let (
        (template (unwrap! (map-get? product-templates template-name) err-not-token-owner))
        (token-id (+ (var-get last-token-id) u1))
        (price (get base-price template))
    )
        (begin
            (asserts! (< (get current-supply template) (get max-supply template)) err-already-minted)
            (try! (stx-transfer? price tx-sender contract-owner))
            (try! (nft-mint? wear-nft token-id tx-sender))
            (map-set token-metadata token-id {
                name: template-name,
                description: (concat template-name " NFT"),
                image: "https://placeholder-image.com",
                product-type: (unwrap-panic (as-max-len? template-name u32)),
                size: size,
                color: color,
                physical-shipped: false,
                tracking-number: none
            })
            (map-set product-templates template-name 
                (merge template { current-supply: (+ (get current-supply template) u1) })
            )
            (let ((current-orders (default-to (list) (map-get? user-orders tx-sender))))
                (map-set user-orders tx-sender (unwrap! (as-max-len? (append current-orders token-id) u50) err-not-token-owner))
            )
            (var-set last-token-id token-id)
            (ok token-id)
        )
    )
)

(define-public (list-for-sale (token-id uint) (price uint))
    (let ((token-owner (unwrap! (nft-get-owner? wear-nft token-id) err-token-not-found)))
        (begin
            (asserts! (is-eq tx-sender token-owner) err-not-token-owner)
            (asserts! (> price u0) err-invalid-price)
            (map-set marketplace-listings token-id {
                seller: tx-sender,
                price: price,
                active: true
            })
            (ok true)
        )
    )
)

(define-public (buy-from-marketplace (token-id uint))
    (let (
        (listing (unwrap! (map-get? marketplace-listings token-id) err-listing-not-found))
        (seller (get seller listing))
        (price (get price listing))
    )
        (begin
            (asserts! (get active listing) err-listing-not-found)
            (try! (stx-transfer? price tx-sender seller))
            (try! (nft-transfer? wear-nft token-id seller tx-sender))
            (map-delete marketplace-listings token-id)
            (ok true)
        )
    )
)

(define-public (cancel-listing (token-id uint))
    (let ((listing (unwrap! (map-get? marketplace-listings token-id) err-listing-not-found)))
        (begin
            (asserts! (is-eq tx-sender (get seller listing)) err-not-token-owner)
            (map-delete marketplace-listings token-id)
            (ok true)
        )
    )
)

(define-public (mark-shipped (token-id uint) (tracking (string-ascii 64)))
    (let ((metadata (unwrap! (map-get? token-metadata token-id) err-token-not-found)))
        (begin
            (asserts! (is-eq tx-sender contract-owner) err-owner-only)
            (map-set token-metadata token-id 
                (merge metadata { 
                    physical-shipped: true,
                    tracking-number: (some tracking)
                })
            )
            (ok true)
        )
    )
)

(define-public (transfer (token-id uint) (sender principal) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender sender) err-not-token-owner)
        (nft-transfer? wear-nft token-id sender recipient)
    )
)

(define-read-only (get-last-token-id)
    (ok (var-get last-token-id))
)

(define-read-only (get-token-uri (token-id uint))
    (ok (some (var-get contract-uri)))
)

(define-read-only (get-owner (token-id uint))
    (ok (nft-get-owner? wear-nft token-id))
)

(define-read-only (get-token-metadata (token-id uint))
    (map-get? token-metadata token-id)
)

(define-read-only (get-product-template (template-name (string-ascii 64)))
    (map-get? product-templates template-name)
)

(define-read-only (get-marketplace-listing (token-id uint))
    (map-get? marketplace-listings token-id)
)

(define-read-only (get-user-orders (user principal))
    (default-to (list) (map-get? user-orders user))
)

(define-read-only (is-shipped (token-id uint))
    (match (map-get? token-metadata token-id)
        metadata (ok (get physical-shipped metadata))
        (err err-token-not-found)
    )
)

(define-read-only (get-tracking-info (token-id uint))
    (match (map-get? token-metadata token-id)
        metadata (ok (get tracking-number metadata))
        (err err-token-not-found)
    )
)