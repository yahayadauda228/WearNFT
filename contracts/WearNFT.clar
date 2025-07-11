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
(define-constant err-rental-not-found (err u107))
(define-constant err-rental-expired (err u108))
(define-constant err-rental-active (err u109))
(define-constant err-invalid-duration (err u110))
(define-constant err-not-renter (err u111))
(define-constant err-subscription-not-found (err u112))
(define-constant err-subscription-expired (err u113))
(define-constant err-already-subscribed (err u114))
(define-constant err-invalid-subscription-tier (err u115))

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

(define-map rental-agreements uint {
    token-id: uint,
    renter: principal,
    owner: principal,
    rental-price: uint,
    start-block: uint,
    end-block: uint,
    active: bool,
    deposit: uint
})

(define-map subscription-plans (string-ascii 32) {
    price-per-block: uint,
    min-duration: uint,
    max-duration: uint,
    discount-percentage: uint,
    active: bool
})

(define-map user-subscriptions principal {
    plan-name: (string-ascii 32),
    start-block: uint,
    end-block: uint,
    tokens-accessed: (list 20 uint),
    renewal-price: uint,
    auto-renew: bool
})

(define-map rental-deposits uint {
    amount: uint,
    refunded: bool
})

(define-data-var rental-agreement-id uint u0)
(define-data-var platform-fee-percentage uint u5)

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

(define-public (create-subscription-plan 
    (plan-name (string-ascii 32))
    (price-per-block uint)
    (min-duration uint)
    (max-duration uint)
    (discount-percentage uint)
)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> price-per-block u0) err-invalid-price)
        (asserts! (< min-duration max-duration) err-invalid-duration)
        (asserts! (<= discount-percentage u100) err-invalid-subscription-tier)
        (map-set subscription-plans plan-name {
            price-per-block: price-per-block,
            min-duration: min-duration,
            max-duration: max-duration,
            discount-percentage: discount-percentage,
            active: true
        })
        (ok true)
    )
)

(define-public (subscribe-to-plan 
    (plan-name (string-ascii 32))
    (duration uint)
    (auto-renew bool)
)
    (let (
        (plan (unwrap! (map-get? subscription-plans plan-name) err-subscription-not-found))
        (start-block stacks-block-height)
        (end-block (+ stacks-block-height duration))
        (base-cost (* (get price-per-block plan) duration))
        (discount-amount (/ (* base-cost (get discount-percentage plan)) u100))
        (final-cost (- base-cost discount-amount))
    )
        (begin
            (asserts! (get active plan) err-subscription-expired)
            (asserts! (>= duration (get min-duration plan)) err-invalid-duration)
            (asserts! (<= duration (get max-duration plan)) err-invalid-duration)
            (asserts! (is-none (map-get? user-subscriptions tx-sender)) err-already-subscribed)
            (try! (stx-transfer? final-cost tx-sender contract-owner))
            (map-set user-subscriptions tx-sender {
                plan-name: plan-name,
                start-block: start-block,
                end-block: end-block,
                tokens-accessed: (list),
                renewal-price: final-cost,
                auto-renew: auto-renew
            })
            (ok true)
        )
    )
)

(define-public (renew-subscription)
    (let (
        (subscription (unwrap! (map-get? user-subscriptions tx-sender) err-subscription-not-found))
        (plan-name (get plan-name subscription))
        (plan (unwrap! (map-get? subscription-plans plan-name) err-subscription-not-found))
        (current-duration (- (get end-block subscription) (get start-block subscription)))
        (new-end-block (+ (get end-block subscription) current-duration))
        (renewal-cost (get renewal-price subscription))
    )
        (begin
            (asserts! (get auto-renew subscription) err-subscription-expired)
            (asserts! (get active plan) err-subscription-expired)
            (try! (stx-transfer? renewal-cost tx-sender contract-owner))
            (map-set user-subscriptions tx-sender 
                (merge subscription { 
                    end-block: new-end-block,
                    tokens-accessed: (list)
                })
            )
            (ok true)
        )
    )
)

(define-public (create-rental-offer 
    (token-id uint)
    (rental-price uint)
    (duration uint)
    (deposit uint)
)
    (let (
        (token-owner (unwrap! (nft-get-owner? wear-nft token-id) err-token-not-found))
        (agreement-id (+ (var-get rental-agreement-id) u1))
    )
        (begin
            (asserts! (is-eq tx-sender token-owner) err-not-token-owner)
            (asserts! (> rental-price u0) err-invalid-price)
            (asserts! (> duration u0) err-invalid-duration)
            (asserts! (> deposit u0) err-invalid-price)
            (map-set rental-agreements agreement-id {
                token-id: token-id,
                renter: tx-sender,
                owner: token-owner,
                rental-price: rental-price,
                start-block: u0,
                end-block: u0,
                active: false,
                deposit: deposit
            })
            (var-set rental-agreement-id agreement-id)
            (ok agreement-id)
        )
    )
)

(define-public (rent-nft 
    (agreement-id uint)
    (rental-duration uint)
)
    (let (
        (agreement (unwrap! (map-get? rental-agreements agreement-id) err-rental-not-found))
        (token-id (get token-id agreement))
        (total-cost (+ (get rental-price agreement) (get deposit agreement)))
        (platform-fee (/ (* (get rental-price agreement) (var-get platform-fee-percentage)) u100))
        (owner-payment (- (get rental-price agreement) platform-fee))
        (start-block stacks-block-height)
        (end-block (+ stacks-block-height rental-duration))
    )
        (begin
            (asserts! (not (get active agreement)) err-rental-active)
            (asserts! (> rental-duration u0) err-invalid-duration)
            (try! (stx-transfer? total-cost tx-sender (as-contract tx-sender)))
            (try! (stx-transfer? owner-payment (as-contract tx-sender) (get owner agreement)))
            (try! (stx-transfer? platform-fee (as-contract tx-sender) contract-owner))
            (map-set rental-agreements agreement-id 
                (merge agreement {
                    renter: tx-sender,
                    start-block: start-block,
                    end-block: end-block,
                    active: true
                })
            )
            (map-set rental-deposits agreement-id {
                amount: (get deposit agreement),
                refunded: false
            })
            (ok true)
        )
    )
)

(define-public (return-rented-nft (agreement-id uint))
    (let (
        (agreement (unwrap! (map-get? rental-agreements agreement-id) err-rental-not-found))
        (deposit-info (unwrap! (map-get? rental-deposits agreement-id) err-rental-not-found))
        (deposit-amount (get amount deposit-info))
    )
        (begin
            (asserts! (get active agreement) err-rental-expired)
            (asserts! (is-eq tx-sender (get renter agreement)) err-not-renter)
            (asserts! (not (get refunded deposit-info)) err-rental-expired)
            (try! (stx-transfer? deposit-amount (as-contract tx-sender) tx-sender))
            (map-set rental-agreements agreement-id 
                (merge agreement { active: false })
            )
            (map-set rental-deposits agreement-id 
                (merge deposit-info { refunded: true })
            )
            (ok true)
        )
    )
)

(define-public (claim-expired-rental (agreement-id uint))
    (let (
        (agreement (unwrap! (map-get? rental-agreements agreement-id) err-rental-not-found))
        (deposit-info (unwrap! (map-get? rental-deposits agreement-id) err-rental-not-found))
        (deposit-amount (get amount deposit-info))
    )
        (begin
            (asserts! (get active agreement) err-rental-expired)
            (asserts! (is-eq tx-sender (get owner agreement)) err-not-token-owner)
            (asserts! (>= stacks-block-height (get end-block agreement)) err-rental-active)
            (asserts! (not (get refunded deposit-info)) err-rental-expired)
            (try! (stx-transfer? deposit-amount (as-contract tx-sender) tx-sender))
            (map-set rental-agreements agreement-id 
                (merge agreement { active: false })
            )
            (map-set rental-deposits agreement-id 
                (merge deposit-info { refunded: true })
            )
            (ok true)
        )
    )
)

(define-public (cancel-subscription)
    (let (
        (subscription (unwrap! (map-get? user-subscriptions tx-sender) err-subscription-not-found))
    )
        (begin
            (map-delete user-subscriptions tx-sender)
            (ok true)
        )
    )
)

(define-public (access-token-with-subscription (token-id uint))
    (let (
        (subscription (unwrap! (map-get? user-subscriptions tx-sender) err-subscription-not-found))
        (current-tokens (get tokens-accessed subscription))
    )
        (begin
            (asserts! (> (get end-block subscription) stacks-block-height) err-subscription-expired)
            (asserts! (< (len current-tokens) u20) err-already-subscribed)
            (map-set user-subscriptions tx-sender 
                (merge subscription {
                    tokens-accessed: (unwrap! (as-max-len? (append current-tokens token-id) u20) err-already-subscribed)
                })
            )
            (ok true)
        )
    )
)

(define-public (set-platform-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-fee u20) err-invalid-price)
        (var-set platform-fee-percentage new-fee)
        (ok true)
    )
)

(define-read-only (get-rental-agreement (agreement-id uint))
    (map-get? rental-agreements agreement-id)
)

(define-read-only (get-subscription-plan (plan-name (string-ascii 32)))
    (map-get? subscription-plans plan-name)
)

(define-read-only (get-user-subscription (user principal))
    (map-get? user-subscriptions user)
)

(define-read-only (get-rental-deposit (agreement-id uint))
    (map-get? rental-deposits agreement-id)
)

(define-read-only (is-rental-active (agreement-id uint))
    (match (map-get? rental-agreements agreement-id)
        agreement (ok (and (get active agreement) (< stacks-block-height (get end-block agreement))))
        (err err-rental-not-found)
    )
)

(define-read-only (is-subscription-active (user principal))
    (match (map-get? user-subscriptions user)
        subscription (ok (> (get end-block subscription) stacks-block-height))
        (err err-subscription-not-found)
    )
)

(define-read-only (calculate-rental-cost (price uint) (duration uint) (deposit uint))
    (let (
        (platform-fee (/ (* price (var-get platform-fee-percentage)) u100))
        (total-cost (+ price deposit platform-fee))
    )
        (ok {
            rental-price: price,
            deposit: deposit,
            platform-fee: platform-fee,
            total-cost: total-cost
        })
    )
)

(define-read-only (get-platform-fee-percentage)
    (ok (var-get platform-fee-percentage))
)