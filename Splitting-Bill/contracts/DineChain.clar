;; DineChain: Main contract for managing dining sessions and payments
;; Contract for handling group dining payments and bill splitting

;; Error Codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-SESSION-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-JOINED (err u102))
(define-constant ERR-INSUFFICIENT-AMOUNT (err u103))
(define-constant ERR-SESSION-CLOSED (err u104))
(define-constant ERR-NOT-RESTAURANT (err u105))

;; Data Maps
(define-map Restaurants 
    principal 
    {
        name: (string-ascii 50),
        verified: bool,
        total-sessions: uint
    }
)

(define-map DiningSessions
    uint  ;; session-id
    {
        restaurant: principal,
        total-required: uint,
        total-collected: uint,
        participants: uint,
        status: (string-ascii 10),  ;; "OPEN", "PAID", "CLOSED"
        created-at: uint
    }
)

(define-map SessionParticipants
    {session-id: uint, participant: principal}
    {
        amount: uint,
        paid: bool
    }
)

;; Session ID counter
(define-data-var next-session-id uint u1)

;; Contract owner
(define-data-var contract-owner principal tx-sender)

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

;; Public functions

;; Register restaurant
(define-public (register-restaurant (name (string-ascii 50)))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (map-set Restaurants tx-sender {
            name: name,
            verified: true,
            total-sessions: u0
        })
        (ok true)
    )
)

;; Create dining session
(define-public (create-session (restaurant principal) (total-amount uint))
    (let
        ((session-id (var-get next-session-id)))
        ;; Verify restaurant is registered
        (asserts! (is-some (get-restaurant restaurant)) ERR-NOT-RESTAURANT)
        ;; Create new session
        (map-set DiningSessions session-id
            {
                restaurant: restaurant,
                total-required: total-amount,
                total-collected: u0,
                participants: u0,
                status: "OPEN",
                created-at: block-height
            }
        )
        ;; Increment session counter
        (var-set next-session-id (+ session-id u1))
        (ok session-id)
    )
)

;; Join session with payment
(define-public (join-session (session-id uint) (amount uint))
    (let
        ((session (unwrap! (get-session session-id) ERR-SESSION-NOT-FOUND))
         (participant-key {session-id: session-id, participant: tx-sender}))
        ;; Verify session is open
        (asserts! (is-eq (get status session) "OPEN") ERR-SESSION-CLOSED)
        ;; Verify not already joined
        (asserts! (is-none (get-participant-info session-id tx-sender)) ERR-ALREADY-JOINED)
        ;; Transfer STX to contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        ;; Update session info
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
                paid: false
            }
        )
        (ok true)
    )
)

;; Complete payment to restaurant
(define-public (complete-payment (session-id uint))
    (let
        ((session (unwrap! (get-session session-id) ERR-SESSION-NOT-FOUND)))
        ;; Verify caller is the restaurant
        (asserts! (is-eq tx-sender (get restaurant session)) ERR-NOT-AUTHORIZED)
        ;; Verify sufficient funds collected
        (asserts! (>= (get total-collected session) (get total-required session)) ERR-INSUFFICIENT-AMOUNT)
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
