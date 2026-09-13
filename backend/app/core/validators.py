"""
Funciones de validación reutilizables para HuellAPP.

Actualmente contiene validaciones de datos nacionales chilenos.

SECURITY:
- Las validaciones críticas deben realizarse en backend.
- El frontend puede repetirlas por UX, pero nunca reemplazarlas.
"""


def is_valid_chilean_rut(rut: str) -> bool:
    """
    Valida un RUT chileno usando su dígito verificador.

    El valor debe venir normalizado, por ejemplo:

        15766669-6
        12345678-K

    Args:
        rut:
            RUT chileno sin puntos y con guion.

    Returns:
        bool:
            True si el formato y dígito verificador son válidos.
            False en caso contrario.
    """

    if not rut or "-" not in rut:
        return False

    try:
        body, verifier = rut.rsplit("-", 1)
    except ValueError:
        return False

    if not body.isdigit():
        return False

    if len(verifier) != 1:
        return False

    verifier = verifier.upper()

    if verifier not in "0123456789K":
        return False

    total = 0
    multiplier = 2

    for digit in reversed(body):
        total += int(digit) * multiplier
        multiplier += 1

        if multiplier > 7:
            multiplier = 2

    remainder = 11 - (total % 11)

    if remainder == 11:
        expected_verifier = "0"
    elif remainder == 10:
        expected_verifier = "K"
    else:
        expected_verifier = str(remainder)

    return verifier == expected_verifier