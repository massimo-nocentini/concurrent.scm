
(import scheme (chicken base) aux unittest concurrent)

(define (ℕ-channel cos j)
  (letchannel-async cos (ch)
    (concurrent-system-spawn cos
      (let C ((i j))
        (concurrent-channel-send ch i)
        (C (add1 i))))
    ch))

(define (primes-channel cos)
  (letchannel-async cos (primes)
    (concurrent-system-spawn cos
      (let head ((nats (ℕ-channel cos 2)))
        (let ((p (concurrent-channel-recv nats)))
          (concurrent-channel-send primes p)
          (head (concurrent-channel-filter nats (λ (n) (> (modulo n p) 0)))))))
    primes))

(define-suite suite

  ((test-empty _)
    (let ((cos (concurrent-system-empty)))
      (concurrent-system-spawn cos
        (print "Hello, World!")
        #;(concurrent-system-yield! cos))
      (concurrent-system-yield! cos)))

  ((test-nat-channel _)
      (let* ((cos (concurrent-system-empty))
             (ch (ℕ-channel cos 0)))
        (⊦= 0 (concurrent-channel-recv ch))
        (⊦= 1 (concurrent-channel-recv ch))
        (⊦= 2 (concurrent-channel-recv ch))
        (⊦= 3 (concurrent-channel-recv ch))))

  ((test-primes-channel _)
      (let* ((cos (concurrent-system-empty))
             (ch (primes-channel cos)))
        (⊦= 0 (concurrent-channel-recv ch))
        (⊦= 1 (concurrent-channel-recv ch))
        (⊦= 2 (concurrent-channel-recv ch))
        (⊦= 3 (concurrent-channel-recv ch))))

)


(unittest/✓ suite)