;; DineChain: Enhanced contract with additional security and functionality
;; Version: 2.0

;; Error Codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-SESSION-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-JOINED (err u102))
(define-constant ERR-INSUFFICIENT-AMOUNT (err u103))
(define-constant ERR-SESSION-CLOSED (err u104))
(define-constant ERR-NOT-RESTAURANT (err u105))
(define-constant ERR-EXPIRED-SESSION (err u106))
(define-constant ERR-INVALID-AMOUNT (err u107))
(define-constant ERR-MAX-PARTICIPANTS (err u108))
(define-constant ERR-RESTAURANT-BLACKLISTED (err u109))
(define-constant ERR-PARTICIPANT-BLACKLISTED (err u110))
(define-constant ERR-SESSION-TIMEOUT (err u111))
(define-constant ERR-DOUBLE-CLAIM (err u112))
(define-constant ERR-INVALID-RESTAURANT (err u113))
(define-constant ERR-INVALID-STATUS (err u114))
(define-constant ERR-RESTAURANT-RATING (err u115))

;; Constants
(define-constant MAX-PARTICIPANTS u20)
(define-constant SESSION-TIMEOUT u144) ;; ~24 hours in blocks
(define-constant MAX-AMOUNT u1000000000) ;; Maximum amount in microSTX
(define-constant MIN-AMOUNT u1000) ;; Minimum amount in microSTX

;; Data Maps
(define-map Restaurants 
    principal 
    {
        name: (string-ascii 50),
        verified: bool,
        total-sessions: uint,
        rating: uint,
        blacklisted: bool,
        last-active: uint
    }
)

(define-map DiningSessions
    uint  ;; session-id
    {
        restaurant: principal,
        total-required: uint,
        total-collected: uint,
        participants: uint,
        status: (string-ascii 10),  ;; "OPEN", "PAID", "CLOSED", "DISPUTED"
        created-at: uint,
        expires-at: uint,
        minimum-per-person: uint,
        dispute-count: uint,
        tips-percentage: uint
    }
)

(define-map SessionParticipants
    {session-id: uint, participant: principal}
    {
        amount: uint,
        paid: bool,
        joined-at: uint,
        tip-amount: uint,
        has-disputed: bool
    }
)

(define-map BlacklistedUsers principal bool)
(define-map DisputeResolutions uint {resolved: bool, winner: principal})
(define-map RestaurantRatings principal {total-ratings: uint, average-rating: uint})

;; Data Variables
(define-data-var next-session-id uint u1)
(define-data-var contract-owner principal tx-sender)
(define-data-var emergency-shutdown bool false)
(define-data-var platform-fee-percentage uint u1) ;; 1% platform fee

;; Read-only functions
(define-read-only (get-session (session-id uint))
    (map-get? DiningSessions session-id)
)

(define-read-only (get-restaurant (restaurant-principal principal))
    (map-get? Restaurants restaurant-principal)
)

(define-read-only (get-participant-info (session-id uint) (participant principal))
    (map-get? SessionParticipants {session-id: session-id, participant: participant})
)

(define-read-only (get-restaurant-rating (restaurant-principal principal))
    (map-get? RestaurantRatings restaurant-principal)
)

(define-read-only (get-contract-info)
    {
        owner: (var-get contract-owner),
        emergency-shutdown: (var-get emergency-shutdown),
        platform-fee: (var-get platform-fee-percentage),
        current-session-id: (var-get next-session-id)
    }
)

(define-read-only (get-session-detailed (session-id uint))
    (let
        ((session (unwrap! (get-session session-id) none)))
        (some {
            session: session,
            is-expired: (is-session-expired session-id),
            total-with-tips: (+ (get total-collected session) 
                               (* (get total-collected session) (get tips-percentage session)))
        })
    )
)

;; Private functions
(define-private (is-contract-operational)
    (not (var-get emergency-shutdown))
)

(define-private (validate-amount (amount uint))
    (and 
        (>= amount MIN-AMOUNT)
        (<= amount MAX-AMOUNT)
    )
)

(define-private (is-session-expired (session-id uint))
    (let
        ((session (unwrap! (map-get? DiningSessions session-id) false)))
        (> block-height (get expires-at session))
    )
)

(define-private (calculate-platform-fee (amount uint))
    (/ (* amount (var-get platform-fee-percentage)) u100)
)

(define-private (update-restaurant-rating (restaurant principal) (new-rating uint))
    (let
        ((current-ratings (default-to 
            {total-ratings: u0, average-rating: u0}
            (map-get? RestaurantRatings restaurant))))
        (map-set RestaurantRatings restaurant
            {
                total-ratings: (+ (get total-ratings current-ratings) u1),
                average-rating: (/ (+ (* (get average-rating current-ratings) 
                                       (get total-ratings current-ratings))
                                    new-rating)
                                 (+ (get total-ratings current-ratings) u1))
            }
        )
        (ok true)
    )
)

;; Public functions
(define-public (register-restaurant (name (string-ascii 50)))
    (begin
        (asserts! (is-contract-operational) ERR-SESSION-CLOSED)
        (asserts! (is-none (get-restaurant tx-sender)) ERR-INVALID-RESTAURANT)
        (map-set Restaurants tx-sender {
            name: name,
            verified: true,
            total-sessions: u0,
            rating: u0,
            blacklisted: false,
            last-active: block-height
        })
        (ok true)
    )
)

(define-public (create-session 
    (restaurant principal) 
    (total-amount uint)
    (minimum-per-person uint)
    (tips-percentage uint))
    (begin
        (asserts! (is-contract-operational) ERR-SESSION-CLOSED)
        (asserts! (validate-amount total-amount) ERR-INVALID-AMOUNT)
        (asserts! (<= tips-percentage u30) ERR-INVALID-AMOUNT) ;; Max 30% tips
        (let
            ((session-id (var-get next-session-id))
             (restaurant-info (unwrap! (get-restaurant restaurant) ERR-NOT-RESTAURANT)))
            ;; Additional checks
            (asserts! (not (get blacklisted restaurant-info)) ERR-RESTAURANT-BLACKLISTED)
            (asserts! (>= (get rating restaurant-info) u1) ERR-NOT-AUTHORIZED)
            ;; Create session
            (map-set DiningSessions session-id
                {
                    restaurant: restaurant,
                    total-required: total-amount,
                    total-collected: u0,
                    participants: u0,
                    status: "OPEN",
                    created-at: block-height,
                    expires-at: (+ block-height SESSION-TIMEOUT),
                    minimum-per-person: minimum-per-person,
                    dispute-count: u0,
                    tips-percentage: tips-percentage
                }
            )
            (var-set next-session-id (+ session-id u1))
            (ok session-id)
        )
    )
)

(define-public (join-session (session-id uint) (amount uint))
    (begin
        (asserts! (is-contract-operational) ERR-SESSION-CLOSED)
        (let
            ((session (unwrap! (get-session session-id) ERR-SESSION-NOT-FOUND))
             (participant-key {session-id: session-id, participant: tx-sender}))
            ;; Enhanced checks
            (asserts! (not (is-session-expired session-id)) ERR-EXPIRED-SESSION)
            (asserts! (< (get participants session) MAX-PARTICIPANTS) ERR-MAX-PARTICIPANTS)
            (asserts! (>= amount (get minimum-per-person session)) ERR-INSUFFICIENT-AMOUNT)
            (asserts! (not (default-to false (map-get? BlacklistedUsers tx-sender))) ERR-PARTICIPANT-BLACKLISTED)
            
            ;; Calculate tips and platform fee
            (let
                ((tip-amount (/ (* amount (get tips-percentage session)) u100))
                 (platform-fee (calculate-platform-fee amount)))
                ;; Transfer total amount including tips and platform fee
                (try! (stx-transfer? (+ amount tip-amount platform-fee) 
                                   tx-sender 
                                   (as-contract tx-sender)))
                
                ;; Update session
                (map-set DiningSessions session-id
                    (merge session {
                        total-collected: (+ (get total-collected session) amount),
                        participants: (+ (get participants session) u1)
                    })
                )
                
                ;; Add participant
                (map-set SessionParticipants participant-key
                    {
                        amount: amount,
                        paid: false,
                        joined-at: block-height,
                        tip-amount: tip-amount,
                        has-disputed: false
                    }
                )
                (ok true)
            )
        )
    )
)

(define-public (complete-payment (session-id uint))
    (let
        ((session (unwrap! (get-session session-id) ERR-SESSION-NOT-FOUND)))
        ;; Verify caller is the restaurant
        (asserts! (is-eq tx-sender (get restaurant session)) ERR-NOT-AUTHORIZED)
        ;; Verify sufficient funds collected
        (asserts! (>= (get total-collected session) (get total-required session)) ERR-INSUFFICIENT-AMOUNT)
        ;; Verify session is open
        (asserts! (is-eq (get status session) "OPEN") ERR-INVALID-STATUS)
        ;; Transfer funds to restaurant
        (try! (as-contract (stx-transfer? 
            (get total-collected session)
            tx-sender
            (get restaurant session)
        )))
        ;; Update session status
        (map-set DiningSessions session-id
            (merge session {status: "PAID"})
        )
        (ok true)
    )
)

(define-public (raise-dispute (session-id uint))
    (let
        ((session (unwrap! (get-session session-id) ERR-SESSION-NOT-FOUND))
         (participant-info (unwrap! (get-participant-info session-id tx-sender) ERR-NOT-AUTHORIZED)))
        (asserts! (not (get has-disputed participant-info)) ERR-DOUBLE-CLAIM)
        (asserts! (is-eq (get status session) "OPEN") ERR-INVALID-STATUS)
        (map-set DiningSessions session-id
            (merge session {
                dispute-count: (+ (get dispute-count session) u1),
                status: "DISPUTED"
            })
        )
        (map-set SessionParticipants 
            {session-id: session-id, participant: tx-sender}
            (merge participant-info {has-disputed: true})
        )
        (ok true)
    )
)

(define-public (claim-refund (session-id uint))
    (let
        ((session (unwrap! (get-session session-id) ERR-SESSION-NOT-FOUND))
         (participant-info (unwrap! (get-participant-info session-id tx-sender) ERR-NOT-AUTHORIZED)))
        (asserts! (is-session-expired session-id) ERR-SESSION-TIMEOUT)
        (asserts! (not (get paid participant-info)) ERR-DOUBLE-CLAIM)
        ;; Process refund
        (try! (as-contract (stx-transfer? 
            (+ (get amount participant-info) (get tip-amount participant-info))
            tx-sender
            tx-sender
        )))
        (map-set SessionParticipants 
            {session-id: session-id, participant: tx-sender}
            (merge participant-info {paid: true})
        )
        (ok true)
    )
)

(define-public (rate-restaurant (restaurant principal) (rating uint))
    (begin
        (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-AMOUNT)
        (unwrap! (update-restaurant-rating restaurant rating) ERR-RESTAURANT-RATING)
        (ok true)
    )
)

(define-public (toggle-emergency-shutdown)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (ok (var-set emergency-shutdown (not (var-get emergency-shutdown))))
    )
)

(define-public (collect-platform-fees)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (let
            ((contract-balance (stx-get-balance (as-contract tx-sender))))
            (try! (as-contract (stx-transfer? 
                contract-balance
                tx-sender
                (var-get contract-owner)
            )))
            (ok contract-balance)
        )
    )
)
