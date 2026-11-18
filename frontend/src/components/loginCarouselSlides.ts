import carrusel1 from '../assets/Carrusel_4.jpg'
import carrusel2 from '../assets/Carrusel_5.jpg'
import carrusel3 from '../assets/Carrusel_6.jpg'

interface LoginCarouselSlide {
  image: string
  alt: string
  category: string
  title: string
  description: string
  position: string
}

// Edita este listado para cambiar fotos y mensajes o agregar nuevas diapositivas.
// "position" define el punto de enfoque de cada foto cuando el panel la recorta.
export const loginCarouselSlides: LoginCarouselSlide[] = [
  {
    image: carrusel1,
    alt: 'Estudiantes y docente compartiendo una actividad en la sala de clases',
    category: 'Educación',
    title: 'Cada aprendizaje deja huella.',
    description: 'Acompañamos experiencias que conectan a las personas con nuevas oportunidades.',
    position: '48% center',
  },
  {
    image: carrusel2,
    alt: 'Jóvenes explorando juntos material de orientación vocacional',
    category: 'Vocación',
    title: 'Un camino por descubrir.',
    description: 'Creamos espacios para reconocer talentos y dar el siguiente paso con confianza.',
    position: 'center center',
  },
  {
    image: carrusel3,
    alt: 'Jóvenes participando juntos en una actividad de encuentro',
    category: 'Comunidad',
    title: 'Juntos construimos futuro.',
    description: 'Cada encuentro es una oportunidad para aprender, compartir y crecer en comunidad.',
    position: '53% center',
  },
]
