package lowprio

func Run(job func()) {
	done := make(chan struct{})
	Go(func() {
		defer close(done)
		job()
	})
	<-done
}
