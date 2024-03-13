
(module concurrent *

	  (import scheme (chicken base) (chicken condition) (chicken foreign) aux fds-queue)

    #>
    #include <zmq.h>
    extern C_word C_zmq_ctx_new (C_word);
    extern C_word C_pthread_create (C_word);
    <#

    (define ZMQ-REP (foreign-value "ZMQ_REP" int))

    (define-record concurrent-system rdyQ)

    (define (concurrent-system-empty)
      (letqueue ((q '()))
        (make-concurrent-system q)))

    (define (concurrent-system-rdyQ-enqueue! cos k)
      (concurrent-system-rdyQ-set! cos (fds-queue-cons k (concurrent-system-rdyQ cos))))

    (define (concurrent-system-rdyQ-dequeue! cos)
      (let* ((rdyQ (concurrent-system-rdyQ cos))
             (k (fds-queue-car rdyQ)))
        (concurrent-system-rdyQ-set! cos (fds-queue-cdr rdyQ))
        k))

    (define (concurrent-system-dispatch! cos)
      (let ((rdyQ (concurrent-system-rdyQ cos)))
        (cond
          ((fds-queue-empty? rdyQ) (signal (condition '(exn message "deadlock"))))
          (else ((concurrent-system-rdyQ-dequeue! cos))))))

    (define (concurrent-system-yield! cos)
      (letcc k 
        (concurrent-system-rdyQ-enqueue! cos k)
        (concurrent-system-dispatch! cos)))

    (define (concurrent-system-spawn! cos thunk)
        (let ((t (letcc j
                    (letcc k (j k))
                    (with-exception-handler (λ (x) (void)) thunk)
                    (concurrent-system-dispatch! cos))))
            (concurrent-system-rdyQ-enqueue! cos t)))

    (define-syntax concurrent-system-spawn
      (syntax-rules ()
        ((_ cos body ...) (concurrent-system-spawn! cos (λ () body ...)))))

    (define zmq-ctx-new (foreign-lambda scheme-object "C_zmq_ctx_new" scheme-object))
    (define pthread-create (foreign-safe-lambda scheme-object "C_pthread_create" scheme-object))

    (define-record concurrent-channel sync? sendQ recvQ cos)

    (define (concurrent-channel-async cos)
      (letqueue ((s '()) (r '()))
        (make-concurrent-channel #f s r cos)))

    (define (concurrent-channel-sync cos)
      (letqueue ((s '()) (r '()))
        (make-concurrent-channel #t s r cos)))
    
    (define (concurrent-channel-send ch msg)
      (cond
        ((concurrent-channel-sync? ch) (void))
        (else (letcc k
                (concurrent-system-rdyQ-enqueue! (concurrent-channel-cos ch) k)
                (cond
                  ((fds-queue-empty? (concurrent-channel-recvQ ch))
                      (concurrent-channel-sendQ-set! ch (fds-queue-cons msg (concurrent-channel-sendQ ch)))
                      (concurrent-system-dispatch! (concurrent-channel-cos ch)))
                  (else (let1 (beta (fds-queue-car (concurrent-channel-recvQ ch)))
                          (concurrent-channel-recvQ-set! ch (fds-queue-cdr (concurrent-channel-recvQ ch)))
                          (beta msg))))))))

    (define (concurrent-channel-recv ch)
      (cond
        ((concurrent-channel-sync? ch) (void))
        (else (cond
                ((fds-queue-empty? (concurrent-channel-sendQ ch))
                   (letcc k 
                      (concurrent-channel-recvQ-set! ch (fds-queue-cons k (concurrent-channel-recvQ ch)))
                      (concurrent-system-dispatch! (concurrent-channel-cos ch))))
                (else (let1 (msg (fds-queue-car (concurrent-channel-sendQ ch)))
                        (concurrent-channel-sendQ-set! ch (fds-queue-cdr (concurrent-channel-sendQ ch)))
                        msg))))))

    (define-syntax letchannel-async
      (syntax-rules ()
        ((_ cos (ch ...) body ...)
         (let ((ch (concurrent-channel-async cos)) ...)
           body ...))))

    (define (concurrent-channel-filter chin p?)
      (let1 (cos (concurrent-channel-cos chin))
        (letchannel-async cos (chout)
          (concurrent-system-spawn cos
            (let loop () 
              (let1 (msg (concurrent-channel-recv chin))
                (when (p? msg) (concurrent-channel-send chout msg))
                (loop))))
          chout)))    
)
