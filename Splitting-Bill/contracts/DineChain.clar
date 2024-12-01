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

;; Data Variables
(define-data-var next-session-id uint u1)
(define-data-var contract-owner principal tx-sender)
(define-data-var emergency-shutdown bool false)
(define-data-var platform-fee-percentage uint u1) ;; 1% platform fee

;; Safety Functions

;; Emergency shutdown toggle
(define-public (toggle-emergency-shutdown)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (ok (var-set emergency-shutdown (not (var-get emergency-shutdown))))
    )
)

;; Check if contract is operational
(define-private (is-contract-operational)
    (not (var-get emergency-shutdown))
)

;; Validate amount
(define-private (validate-amount (amount uint))
    (and 
        (>= amount MIN-AMOUNT)
        (<= amount MAX-AMOUNT)
    )
)

;; Check session expiry
(define-private (is-session-expired (session-id uint))
    (let
        ((session (unwrap! (get-session session-id) false)))
        (> block-height (get expires-at session))
    )
)

;; Enhanced Public Functions

;; Create dining session with more parameters
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

;; Enhanced join session with tips handling
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
            
            ;; Calculate tips
            (let
                ((tip-amount (/ (* amount (get tips-percentage session)) u100)))
                ;; Transfer total amount including tips
                (try! (stx-transfer? (+ amount tip-amount) tx-sender (as-contract tx-sender)))
                
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

;; Dispute handling
(define-public (raise-dispute (session-id uint))
    (let
        ((session (unwrap! (get-session session-id) ERR-SESSION-NOT-FOUND))
         (participant-info (unwrap! (get-participant-info session-id tx-sender) ERR-NOT-AUTHORIZED)))
        (asserts! (not (get has-disputed participant-info)) ERR-DOUBLE-CLAIM)
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

;; Refund function for expired sessions
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

;; Platform fee collection
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

;; Additional getters for transparency
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
