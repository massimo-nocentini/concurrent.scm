
(import scheme (chicken base) aux unittest concurrent (chicken pretty-print))

(define (ℕ-channel ch j)
  (concurrent-system-spawn (concurrent-channel-cos ch)
    (let C ((i j))
      (concurrent-channel-send ch i)
      (C (add1 i)))))

(define (primes-channel cos primes)
  (concurrent-system-spawn cos
    (letchannel cos ((ℕ (concurrent-channel-sync? primes)))
      (ℕ-channel ℕ 2)
      (let head ((nats ℕ))
        (let ((p (concurrent-channel-recv nats)))
          (concurrent-channel-send primes p)
          (letchannel cos ((filtered (concurrent-channel-sync? primes)))
            (concurrent-channel-filter nats filtered (λ (n) (> (modulo n p) 0)))
            (head filtered)))))))

(define-suite suite

  ((test-empty _)
    (let ((cos (concurrent-system-empty)))
      (concurrent-system-spawn cos
        (print "Hello, World!")
        #;(concurrent-system-yield! cos))
      (concurrent-system-yield! cos)))

  ((test-nat-channel-sync _)
      (let ((cos (concurrent-system-empty)))
        (letchannel cos ((ach #f) (sch #f))
          (ℕ-channel ach 0)
          (ℕ-channel sch 0)
          (⊦= 0 (concurrent-channel-recv ach))
          (⊦= 0 (concurrent-channel-recv sch))
          (⊦= 1 (concurrent-channel-recv ach))
          (⊦= 1 (concurrent-channel-recv sch))
          (⊦= 2 (concurrent-channel-recv ach))
          (⊦= 2 (concurrent-channel-recv sch))
          (⊦= 3 (concurrent-channel-recv ach))
          (⊦= 3 (concurrent-channel-recv sch)))))

  ((test-primes-channel _)
      (let* ((cos (concurrent-system-empty))
             (limit 10))
        (letchannel cos ((ach #f) (sch #t))
          (primes-channel cos ach)
          (primes-channel cos sch)
          (letrec ((primes (λ (ch n lst)
                            (if (> n limit)
                                (reverse lst)
                                (let ((p (concurrent-channel-recv ch)))
                                  #;(print n "nth " p)
                                  (primes ch (add1 n) (cons p lst)))))))
            (⊦= '(2 3 5 7 11 13 17 19 23 29) (primes ach 1 '()))
            (⊦= '(2 3 5 7 11 13 17 19 23 29) (primes sch 1 '()))))))

  

)


(unittest/✓ suite)