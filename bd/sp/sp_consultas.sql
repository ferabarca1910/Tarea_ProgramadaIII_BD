-- ============================================================
-- SP_CONSULTAS: Consultas del portal web y CRUD de empleados
-- ============================================================

USE PlanillaObrera;
GO

-- ============================================================
-- SP: Login de usuario
-- ============================================================
IF OBJECT_ID('sp_Login', 'P') IS NOT NULL DROP PROCEDURE sp_Login;
GO
CREATE PROCEDURE sp_Login
    @Username   VARCHAR(50),
    @Password   VARCHAR(255),
    @IPOrigen   VARCHAR(45),
    @IdUsuario  INT OUTPUT,
    @Tipo TINYINT OUTPUT,
    @Exitoso    BIT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        @IdUsuario   = IdUsuario,
        @Tipo = Tipo
    FROM dbo.Usuario
    WHERE Username = @Username
      AND PasswordHash = @Password  -- En prod usar HASHBYTES
      AND Activo = 1;

    IF @IdUsuario IS NOT NULL
    BEGIN
        SET @Exitoso = 1;
        EXEC sp_RegistrarEvento @IdUsuario, 1, @IPOrigen,
            N'{"username":"' + @Username + '","resultado":"exitoso"}';
    END
    ELSE
    BEGIN
        SET @Exitoso = 0;
        -- Registrar intento fallido con IdUsuario=0 (sistema)
        EXEC sp_RegistrarEvento 1, 2, @IPOrigen,
            N'{"username":"' + @Username + '","resultado":"fallido"}';
    END;
END;
GO
