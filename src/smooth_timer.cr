# Elapsed time exponential moving average
# α = 0.1 gives roughly a 10-frame smoothing window at 60 fps.
struct SmoothTimer
  getter value = 0.0_f64

  def measure(&)
    t0 = Time.instant
    yield
    ms = (Time.instant - t0).total_milliseconds
    @value = @value * 0.9 + ms * 0.1
  end
end
