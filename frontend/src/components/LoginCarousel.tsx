import { useEffect, useId, useRef, useState } from 'react'
import { loginCarouselSlides as slides } from './loginCarouselSlides'

import '../styles/login-carousel.css'

// Cambia este valor para ajustar el tiempo de lectura entre diapositivas.
const AUTOPLAY_DELAY_MS = 15000
const REDUCED_MOTION_QUERY = '(prefers-reduced-motion: reduce)'

export default function LoginCarousel() {
  const [current, setCurrent] = useState(0)
  const [paused, setPaused] = useState(false)
  const [hovered, setHovered] = useState(false)
  const [focused, setFocused] = useState(false)
  const [reducedMotion, setReducedMotion] = useState(
    () => window.matchMedia(REDUCED_MOTION_QUERY).matches,
  )
  const [pageVisible, setPageVisible] = useState(() => !document.hidden)
  const gestureStart = useRef<{ x: number; y: number } | null>(null)
  const instructionsId = useId()
  const slidesId = useId()

  // Detiene la rotación al interactuar, ocultar la pestaña o reducir movimiento.
  const playing = slides.length > 1 && !paused && !hovered && !focused
    && !reducedMotion && pageVisible

  useEffect(() => {
    const motionPreference = window.matchMedia(REDUCED_MOTION_QUERY)
    const updateMotion = () => setReducedMotion(motionPreference.matches)
    const updateVisibility = () => setPageVisible(!document.hidden)

    motionPreference.addEventListener('change', updateMotion)
    document.addEventListener('visibilitychange', updateVisibility)

    // Retira los listeners al salir del login para evitar suscripciones duplicadas.
    return () => {
      motionPreference.removeEventListener('change', updateMotion)
      document.removeEventListener('visibilitychange', updateVisibility)
    }
  }, [])

  useEffect(() => {
    if (!playing) return

    const timer = window.setTimeout(() => {
      setCurrent((index) => (index + 1) % slides.length)
    }, AUTOPLAY_DELAY_MS)

    // Cada cambio o pausa cancela el temporizador y permite una nueva espera completa.
    return () => window.clearTimeout(timer)
  }, [current, playing])

  const move = (step: number) => {
    setCurrent((index) => (index + step + slides.length) % slides.length)
  }

  return (
    <section
      className="login-carousel"
      aria-roledescription="carrusel"
      aria-label="Historias de Fundación Huella"
      aria-describedby={instructionsId}
      onPointerEnter={(event) => {
        if (event.pointerType === 'mouse') setHovered(true)
      }}
      onPointerLeave={() => {
        setHovered(false)
        gestureStart.current = null
      }}
      onFocusCapture={() => setFocused(true)}
      onBlurCapture={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget)) setFocused(false)
      }}
      onKeyDown={(event) => {
        // Las flechas funcionan solo dentro del carrusel, sin afectar los inputs.
        if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
          event.preventDefault()
          move(event.key === 'ArrowLeft' ? -1 : 1)
        }
      }}
      onPointerDown={(event) => {
        // Reserva los gestos para la foto y deja los botones con su clic habitual.
        if (event.pointerType === 'mouse' || (event.target as Element).closest('button')) return
        gestureStart.current = { x: event.clientX, y: event.clientY }
      }}
      onPointerUp={(event) => {
        const start = gestureStart.current
        gestureStart.current = null
        if (!start) return

        const distanceX = event.clientX - start.x
        const distanceY = event.clientY - start.y
        // Exige un gesto horizontal claro para conservar el scroll vertical móvil.
        if (Math.abs(distanceX) > 48 && Math.abs(distanceX) > Math.abs(distanceY)) {
          move(distanceX < 0 ? 1 : -1)
        }
      }}
      onPointerCancel={() => { gestureStart.current = null }}
    >
      <p id={instructionsId} className="login-carousel__sr-only">
        Selecciona una diapositiva con los indicadores o usa las flechas del teclado.
        En pantallas táctiles puedes deslizar la imagen.
      </p>

      <div className="login-carousel__slides" id={slidesId}>
        {/* Foto y mensaje cambian juntos; las demás diapositivas se ocultan al lector. */}
        {slides.map((slide, index) => (
          <article
            key={slide.image}
            className={`login-carousel__slide${index === current ? ' login-carousel__slide--active' : ''}`}
            role="group"
            aria-roledescription="diapositiva"
            aria-label={`${index + 1} de ${slides.length}`}
            aria-hidden={index !== current}
          >
            <img
              className="login-carousel__image"
              src={slide.image}
              alt={slide.alt}
              style={{ objectPosition: slide.position }}
              fetchPriority={index === 0 ? 'high' : 'auto'}
              decoding="async"
              draggable={false}
            />
            <div className="login-carousel__caption">
              <p className="login-carousel__category">{slide.category}</p>
              <h2 className="login-carousel__title">{slide.title}</h2>
              <p className="login-carousel__description">{slide.description}</p>
              <p className="login-carousel__signature">Fundación Huella</p>
            </div>
          </article>
        ))}
      </div>

      <header className="login-carousel__header">
        <div className="login-carousel__brand">
          <span>HuellApp</span>
          <span>Formación y vocación</span>
        </div>
        {/* La pausa siempre está disponible, también sin mouse. */}
        <button
          className="login-carousel__button"
          type="button"
          onClick={() => setPaused((value) => !value)}
          aria-label={paused ? 'Reanudar carrusel' : 'Pausar carrusel'}
          aria-pressed={paused}
          aria-controls={slidesId}
          disabled={reducedMotion}
          title={reducedMotion ? 'Reproducción automática desactivada por la preferencia de movimiento' : undefined}
        >
          <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
            {paused || reducedMotion ? <path d="m9 5 10 7-10 7Z" /> : <path d="M9 5v14M15 5v14" />}
          </svg>
        </button>
      </header>

      <footer className="login-carousel__footer">
        <div className="login-carousel__pagination" role="group" aria-label="Elegir diapositiva">
          {slides.map((slide, index) => (
            <button
              key={slide.image}
              className="login-carousel__dot"
              type="button"
              onClick={() => setCurrent(index)}
              aria-label={`Ver diapositiva ${index + 1}: ${slide.category}`}
              aria-current={index === current ? 'true' : undefined}
              aria-controls={slidesId}
            />
          ))}
        </div>

        <span className="login-carousel__counter" aria-hidden="true">
          {String(current + 1).padStart(2, '0')}
          <span> / {String(slides.length).padStart(2, '0')}</span>
        </span>

        {/* Las flechas aparecen con hover o foco; en táctil permanecen visibles. */}
        <div className="login-carousel__arrows">
          {([-1, 1] as const).map((step) => (
            <button
              key={step}
              className="login-carousel__button"
              type="button"
              onClick={() => move(step)}
              aria-label={step === -1 ? 'Diapositiva anterior' : 'Diapositiva siguiente'}
              aria-controls={slidesId}
            >
              <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                <path d={step === -1 ? 'm14 6-6 6 6 6M8 12h12' : 'm10 6 6 6-6 6M16 12H4'} />
              </svg>
            </button>
          ))}
        </div>
      </footer>

      {/* Anuncia los cambios manuales; la reproducción automática permanece silenciosa. */}
      <p className="login-carousel__sr-only" aria-live={playing ? 'off' : 'polite'} aria-atomic="true">
        {`Diapositiva ${current + 1} de ${slides.length}: ${slides[current].title}`}
      </p>
    </section>
  )
}
