;; Product Review and Rating System
;; Enables customers to review and rate physical products after delivery

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-INVALID-RATING (err u401))
(define-constant ERR-ALREADY-REVIEWED (err u402))
(define-constant ERR-TOKEN-NOT-FOUND (err u403))
(define-constant ERR-NOT-TOKEN-OWNER (err u404))
(define-constant ERR-PRODUCT-NOT-SHIPPED (err u405))
(define-constant ERR-REVIEW-NOT-FOUND (err u406))
(define-constant ERR-INVALID-HELPFULNESS (err u407))
(define-constant ERR-CANNOT-VOTE-OWN-REVIEW (err u408))

;; Track individual product reviews
(define-map product-reviews
    {token-id: uint, reviewer: principal}
    {
        rating: uint,
        title: (string-ascii 64),
        review-text: (string-ascii 512),
        fit-rating: uint,
        quality-rating: uint,
        delivery-rating: uint,
        review-date: uint,
        verified-purchase: bool,
        helpful-votes: uint,
        unhelpful-votes: uint
    }
)

;; Track template-level aggregate ratings
(define-map template-ratings
    (string-ascii 64)  ;; template name
    {
        total-reviews: uint,
        average-rating: uint,
        total-rating-points: uint,
        five-star-count: uint,
        four-star-count: uint,
        three-star-count: uint,
        two-star-count: uint,
        one-star-count: uint,
        average-fit: uint,
        average-quality: uint,
        average-delivery: uint
    }
)

;; Track review helpfulness votes
(define-map review-helpfulness
    {token-id: uint, reviewer: principal, voter: principal}
    {
        helpful: bool,
        vote-date: uint
    }
)

;; Track user review statistics
(define-map reviewer-stats
    principal
    {
        total-reviews: uint,
        average-rating-given: uint,
        helpful-review-count: uint,
        reviewer-credibility: uint,
        last-review-date: uint
    }
)

;; Data variables
(define-data-var min-rating uint u1)
(define-data-var max-rating uint u5)
(define-data-var min-review-length uint u10)
(define-data-var total-platform-reviews uint u0)

;; Submit a product review
(define-public (submit-review 
    (token-id uint)
    (rating uint)
    (title (string-ascii 64))
    (review-text (string-ascii 512))
    (fit-rating uint)
    (quality-rating uint)
    (delivery-rating uint))
    (let (
        (token-owner (unwrap! (contract-call? .WearNFT get-owner token-id) ERR-TOKEN-NOT-FOUND))
        (token-metadata (unwrap! (contract-call? .WearNFT get-token-metadata token-id) ERR-TOKEN-NOT-FOUND))
        (existing-review (map-get? product-reviews {token-id: token-id, reviewer: tx-sender}))
        (template-name (get product-type token-metadata))
    )
    ;; Validate review eligibility
    (asserts! (is-eq (unwrap! token-owner ERR-TOKEN-NOT-FOUND) tx-sender) ERR-NOT-TOKEN-OWNER)
    (asserts! (get physical-shipped token-metadata) ERR-PRODUCT-NOT-SHIPPED)
    (asserts! (is-none existing-review) ERR-ALREADY-REVIEWED)
    
    ;; Validate ratings
    (asserts! (and (>= rating (var-get min-rating)) (<= rating (var-get max-rating))) ERR-INVALID-RATING)
    (asserts! (and (>= fit-rating u1) (<= fit-rating u5)) ERR-INVALID-RATING)
    (asserts! (and (>= quality-rating u1) (<= quality-rating u5)) ERR-INVALID-RATING)
    (asserts! (and (>= delivery-rating u1) (<= delivery-rating u5)) ERR-INVALID-RATING)
    (asserts! (>= (len review-text) (var-get min-review-length)) ERR-INVALID-RATING)
    
    ;; Store the review
    (map-set product-reviews {token-id: token-id, reviewer: tx-sender}
        {
            rating: rating,
            title: title,
            review-text: review-text,
            fit-rating: fit-rating,
            quality-rating: quality-rating,
            delivery-rating: delivery-rating,
            review-date: stacks-block-height,
            verified-purchase: true,
            helpful-votes: u0,
            unhelpful-votes: u0
        }
    )
    
    ;; Update template aggregate ratings
    (unwrap! (update-template-ratings template-name rating fit-rating quality-rating delivery-rating) ERR-INVALID-RATING)
    
    ;; Update reviewer statistics
    (unwrap! (update-reviewer-stats tx-sender rating) ERR-INVALID-RATING)
    
    (var-set total-platform-reviews (+ (var-get total-platform-reviews) u1))
    (ok true)
    )
)

;; Update template aggregate ratings
(define-private (update-template-ratings 
    (template-name (string-ascii 64))
    (new-rating uint)
    (fit-rating uint)
    (quality-rating uint)
    (delivery-rating uint))
    (let (
        (current-ratings (default-to 
            {total-reviews: u0, average-rating: u0, total-rating-points: u0,
             five-star-count: u0, four-star-count: u0, three-star-count: u0,
             two-star-count: u0, one-star-count: u0, average-fit: u0,
             average-quality: u0, average-delivery: u0}
            (map-get? template-ratings template-name)))
        (new-total-reviews (+ (get total-reviews current-ratings) u1))
        (new-total-points (+ (get total-rating-points current-ratings) new-rating))
        (new-average (/ new-total-points new-total-reviews))
        (new-fit-avg (/ (+ (* (get average-fit current-ratings) (get total-reviews current-ratings)) fit-rating) new-total-reviews))
        (new-quality-avg (/ (+ (* (get average-quality current-ratings) (get total-reviews current-ratings)) quality-rating) new-total-reviews))
        (new-delivery-avg (/ (+ (* (get average-delivery current-ratings) (get total-reviews current-ratings)) delivery-rating) new-total-reviews))
    )
    
    ;; Update star counts
    (let (
        (updated-ratings (merge current-ratings 
            {
                total-reviews: new-total-reviews,
                average-rating: new-average,
                total-rating-points: new-total-points,
                average-fit: new-fit-avg,
                average-quality: new-quality-avg,
                average-delivery: new-delivery-avg
            }))
    )
    (map-set template-ratings template-name
        (merge updated-ratings (increment-star-count updated-ratings new-rating))
    )
    (ok true)
    )
    )
)

;; Helper function to increment star count based on rating
(define-private (increment-star-count (ratings {total-reviews: uint, average-rating: uint, total-rating-points: uint, five-star-count: uint, four-star-count: uint, three-star-count: uint, two-star-count: uint, one-star-count: uint, average-fit: uint, average-quality: uint, average-delivery: uint}) (rating uint))
    (if (is-eq rating u5)
        {five-star-count: (+ (get five-star-count ratings) u1), four-star-count: (get four-star-count ratings), three-star-count: (get three-star-count ratings), two-star-count: (get two-star-count ratings), one-star-count: (get one-star-count ratings)}
        (if (is-eq rating u4)
            {five-star-count: (get five-star-count ratings), four-star-count: (+ (get four-star-count ratings) u1), three-star-count: (get three-star-count ratings), two-star-count: (get two-star-count ratings), one-star-count: (get one-star-count ratings)}
            (if (is-eq rating u3)
                {five-star-count: (get five-star-count ratings), four-star-count: (get four-star-count ratings), three-star-count: (+ (get three-star-count ratings) u1), two-star-count: (get two-star-count ratings), one-star-count: (get one-star-count ratings)}
                (if (is-eq rating u2)
                    {five-star-count: (get five-star-count ratings), four-star-count: (get four-star-count ratings), three-star-count: (get three-star-count ratings), two-star-count: (+ (get two-star-count ratings) u1), one-star-count: (get one-star-count ratings)}
                    {five-star-count: (get five-star-count ratings), four-star-count: (get four-star-count ratings), three-star-count: (get three-star-count ratings), two-star-count: (get two-star-count ratings), one-star-count: (+ (get one-star-count ratings) u1)}
                )
            )
        )
    )
)

;; Update reviewer statistics
(define-private (update-reviewer-stats (reviewer principal) (rating uint))
    (let (
        (current-stats (default-to 
            {total-reviews: u0, average-rating-given: u0, helpful-review-count: u0,
             reviewer-credibility: u50, last-review-date: u0}
            (map-get? reviewer-stats reviewer)))
        (new-total (+ (get total-reviews current-stats) u1))
        (total-rating-points (+ (* (get average-rating-given current-stats) (get total-reviews current-stats)) rating))
        (new-average (/ total-rating-points new-total))
        (new-credibility (if (<= (+ (get reviewer-credibility current-stats) u2) u100)
                            (+ (get reviewer-credibility current-stats) u2)
                            u100))
    )
    
    (map-set reviewer-stats reviewer
        {
            total-reviews: new-total,
            average-rating-given: new-average,
            helpful-review-count: (get helpful-review-count current-stats),
            reviewer-credibility: new-credibility,
            last-review-date: stacks-block-height
        }
    )
    (ok true)
    )
)

;; Vote on review helpfulness
(define-public (vote-review-helpfulness 
    (token-id uint)
    (reviewer principal)
    (helpful bool))
    (let (
        (review (unwrap! (map-get? product-reviews {token-id: token-id, reviewer: reviewer}) ERR-REVIEW-NOT-FOUND))
        (existing-vote (map-get? review-helpfulness {token-id: token-id, reviewer: reviewer, voter: tx-sender}))
    )
    ;; Validate vote
    (asserts! (not (is-eq tx-sender reviewer)) ERR-CANNOT-VOTE-OWN-REVIEW)
    (asserts! (is-none existing-vote) ERR-ALREADY-REVIEWED)
    
    ;; Record vote
    (map-set review-helpfulness {token-id: token-id, reviewer: reviewer, voter: tx-sender}
        {
            helpful: helpful,
            vote-date: stacks-block-height
        }
    )
    
    ;; Update review helpfulness counts
    (if helpful
        (map-set product-reviews {token-id: token-id, reviewer: reviewer}
            (merge review {helpful-votes: (+ (get helpful-votes review) u1)})
        )
        (map-set product-reviews {token-id: token-id, reviewer: reviewer}
            (merge review {unhelpful-votes: (+ (get unhelpful-votes review) u1)})
        )
    )
    
    ;; Update reviewer credibility if helpful vote
    (if helpful
        (let ((reviewer-stats-data (default-to 
                {total-reviews: u0, average-rating-given: u0, helpful-review-count: u0,
                 reviewer-credibility: u50, last-review-date: u0}
                (map-get? reviewer-stats reviewer))))
            (map-set reviewer-stats reviewer
                (merge reviewer-stats-data 
                    {
                        helpful-review-count: (+ (get helpful-review-count reviewer-stats-data) u1),
                        reviewer-credibility: (if (<= (+ (get reviewer-credibility reviewer-stats-data) u1) u100)
                                                 (+ (get reviewer-credibility reviewer-stats-data) u1)
                                                 u100)
                    }
                )
            )
        )
        true
    )
    
    (ok true)
    )
)

;; Get review for specific token and reviewer
(define-read-only (get-product-review (token-id uint) (reviewer principal))
    (map-get? product-reviews {token-id: token-id, reviewer: reviewer})
)

;; Get template aggregate ratings
(define-read-only (get-template-ratings (template-name (string-ascii 64)))
    (map-get? template-ratings template-name)
)

;; Get reviewer statistics
(define-read-only (get-reviewer-stats (reviewer principal))
    (map-get? reviewer-stats reviewer)
)

;; Check if user can review a product
(define-read-only (can-review-product (token-id uint) (user principal))
    {
        can-review: false,
        owns-token: false,
        is-shipped: false,
        already-reviewed: (is-some (map-get? product-reviews {token-id: token-id, reviewer: user}))
    }
)

;; Get review helpfulness vote
(define-read-only (get-review-vote (token-id uint) (reviewer principal) (voter principal))
    (map-get? review-helpfulness {token-id: token-id, reviewer: reviewer, voter: voter})
)

;; Calculate review helpfulness ratio
(define-read-only (calculate-review-helpfulness (token-id uint) (reviewer principal))
    (let (
        (review (map-get? product-reviews {token-id: token-id, reviewer: reviewer}))
    )
    (match review
        review-data (let (
            (helpful (get helpful-votes review-data))
            (unhelpful (get unhelpful-votes review-data))
            (total-votes (+ helpful unhelpful))
        )
        (if (> total-votes u0)
            (/ (* helpful u100) total-votes)
            u0
        ))
        u0
    )
    )
)

;; Get platform review statistics
(define-read-only (get-platform-review-stats)
    {
        total-reviews: (var-get total-platform-reviews),
        min-rating: (var-get min-rating),
        max-rating: (var-get max-rating),
        min-review-length: (var-get min-review-length)
    }
)

;; Get review summary for template
(define-read-only (get-template-review-summary (template-name (string-ascii 64)))
    (let (
        (ratings (map-get? template-ratings template-name))
    )
    (match ratings
        rating-data {
            average-rating: (get average-rating rating-data),
            total-reviews: (get total-reviews rating-data),
            rating-breakdown: {
                five-star: (get five-star-count rating-data),
                four-star: (get four-star-count rating-data),
                three-star: (get three-star-count rating-data),
                two-star: (get two-star-count rating-data),
                one-star: (get one-star-count rating-data)
            },
            detailed-scores: {
                fit: (get average-fit rating-data),
                quality: (get average-quality rating-data),
                delivery: (get average-delivery rating-data)
            }
        }
        {
            average-rating: u0,
            total-reviews: u0,
            rating-breakdown: {five-star: u0, four-star: u0, three-star: u0, two-star: u0, one-star: u0},
            detailed-scores: {fit: u0, quality: u0, delivery: u0}
        }
    )
    )
)
