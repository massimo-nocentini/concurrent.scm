
(import aux unittest concurrent)

(define-suite suite

  ((test-empty _)
    (let ((cos (concurrent-system-empty)))
      (concurrent-system-spawn cos 
        (print "Hello, World!"))
      #;(concurrent-system-dispatch! cos)))

  ((test-nat-channel _)
      (let* ((cos (concurrent-system-empty))
             (ch (concurrent-channel-async cos)))

        (concurrent-system-spawn cos
          (let count ((i 0))
            (concurrent-channel-send ch i)
            (count (add1 i))))

        (⊦= 0 (concurrent-channel-recv ch))
        (⊦= 1 (concurrent-channel-recv ch))
        (⊦= 2 (concurrent-channel-recv ch))
        (⊦= 3 (concurrent-channel-recv ch))))

)


(unittest/✓ suite)