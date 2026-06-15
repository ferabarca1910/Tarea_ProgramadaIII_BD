
USE PlanillaObrera;
GO
IF OBJECT_ID('dbo.fn_EsFeriadoODomingo', 'FN') IS NOT NULL DROP FUNCTION dbo.fn_EsFeriadoODomingo;
GO
CREATE FUNCTION dbo.fn_EsFeriadoODomingo(@fecha DATE)
RETURNS BIT
AS
BEGIN
    -- DATEPART: 1=domingo, 7=sábado en SQL Server (datefirst=7 default)
    IF DATEPART(WEEKDAY, @fecha) = 1  RETURN 1;  -- domingo
    IF EXISTS (SELECT 1 FROM dbo.Feriado WHERE Fecha = @fecha) RETURN 1;
    RETURN 0;
END;
GO


IF OBJECT_ID('sp_RegistrarEvento', 'P') IS NOT NULL DROP PROCEDURE sp_RegistrarEvento;
GO
CREATE PROCEDURE sp_RegistrarEvento
    @IdUsuario      INT,
    @IdTipoEvento   INT,
    @IPOrigen       VARCHAR(45),
    @Parametros     NVARCHAR(MAX) = NULL,
    @DatosAntes     NVARCHAR(MAX) = NULL,
    @DatosDespues   NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.BitacoraEvento (IdUsuario, IdTipoEvento, IPOrigen, FechaHora, Parametros, DatosAntes, DatosDespues)
    VALUES (@IdUsuario, @IdTipoEvento, @IPOrigen, GETDATE(), @Parametros, @DatosAntes, @DatosDespues);
END;
GO


IF OBJECT_ID('sp_ProcesarAsistencia', 'P') IS NOT NULL DROP PROCEDURE sp_ProcesarAsistencia;
GO
CREATE PROCEDURE sp_ProcesarAsistencia
    @ValorDocumento     VARCHAR(30),
    @FechaHoraEntrada   DATETIME,
    @FechaHoraSalida    DATETIME,
    @IdUsuarioSistema   INT,
    @IPOrigen           VARCHAR(45) = '127.0.0.1'
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @IdEmpleado     INT;
        DECLARE @IdPuesto       INT;
        DECLARE @SalarioXHora   DECIMAL(10,2);

        SELECT
            @IdEmpleado   = e.IdEmpleado,
            @IdPuesto     = e.IdPuesto,
            @SalarioXHora = p.SalarioXHora
        FROM dbo.Empleado e
        INNER JOIN dbo.Puesto p ON e.IdPuesto = p.IdPuesto
        WHERE e.ValorDocumento = @ValorDocumento
          AND e.Activo = 1;

        IF @IdEmpleado IS NULL
        BEGIN
            RAISERROR('Empleado con documento %s no encontrado.', 16, 1, @ValorDocumento);
            ROLLBACK; RETURN;
        END;

   
        DECLARE @FechaEntrada   DATE = CAST(@FechaHoraEntrada AS DATE);
        DECLARE @IdTipoJornada  INT;
        DECLARE @HoraFinJornada TIME;


        SELECT TOP 1
            @IdTipoJornada  = jes.IdTipoJornada,
            @HoraFinJornada = tj.HoraFin
        FROM dbo.JornadaEmpleadoSemana jes
        INNER JOIN dbo.TipoJornada tj ON jes.IdTipoJornada = tj.IdTipoJornada
        WHERE jes.IdEmpleado = @IdEmpleado
          AND jes.FechaInicioSemana <= @FechaEntrada
        ORDER BY jes.FechaInicioSemana DESC;

        IF @IdTipoJornada IS NULL
        BEGIN
            RAISERROR('No hay jornada asignada para el empleado %d en la fecha %s.', 16, 1, @IdEmpleado, CONVERT(VARCHAR,@FechaEntrada,103));
            ROLLBACK; RETURN;
        END;


        DECLARE @IdPlanillaSemXEmpleado INT;

        SELECT TOP 1 @IdPlanillaSemXEmpleado = pse.IdPlanillaSemXEmpleado
        FROM dbo.PlanillaSemXEmpleado pse
        INNER JOIN dbo.SemanaPlanilla sp ON pse.IdSemanaPlanilla = sp.IdSemanaPlanilla
        WHERE pse.IdEmpleado = @IdEmpleado
          AND sp.Cerrada = 0
          AND sp.FechaInicio <= @FechaEntrada
          AND sp.FechaFin    >= @FechaEntrada;

        IF @IdPlanillaSemXEmpleado IS NULL
        BEGIN
            RAISERROR('No hay planilla semanal abierta para el empleado %d.', 16, 1, @IdEmpleado);
            ROLLBACK; RETURN;
        END;

        DECLARE @IdMarca INT;
        INSERT INTO dbo.MarcaAsistencia (IdEmpleado, FechaHoraEntrada, FechaHoraSalida, FechaOperacion)
        VALUES (@IdEmpleado, @FechaHoraEntrada, @FechaHoraSalida, @FechaEntrada);
        SET @IdMarca = SCOPE_IDENTITY();

        DECLARE @FinJornadaDT DATETIME;

        SELECT @FinJornadaDT =
            CASE
                WHEN tj.HoraFin <= tj.HoraInicio  -- cruza medianoche
                    THEN CAST(DATEADD(DAY,1,@FechaEntrada) AS DATETIME) + CAST(tj.HoraFin AS DATETIME) - CAST('00:00:00' AS DATETIME)
                ELSE
                    CAST(@FechaEntrada AS DATETIME) + CAST(tj.HoraFin AS DATETIME) - CAST('00:00:00' AS DATETIME)
            END
        FROM dbo.TipoJornada tj WHERE tj.IdTipoJornada = @IdTipoJornada;

        DECLARE @MinutosTrabajados   INT = DATEDIFF(MINUTE, @FechaHoraEntrada, @FechaHoraSalida);
        DECLARE @MinutosJornada      INT = DATEDIFF(MINUTE, @FechaHoraEntrada, @FinJornadaDT);
        IF @MinutosJornada < 0 SET @MinutosJornada = 0;

  
        DECLARE @MinutosOrdinarios   INT = CASE WHEN @MinutosTrabajados <= @MinutosJornada THEN @MinutosTrabajados ELSE @MinutosJornada END;
        DECLARE @HorasOrdinarias     INT = @MinutosOrdinarios / 60;

  
        DECLARE @MinutosExtra        INT = CASE WHEN @MinutosTrabajados > @MinutosJornada THEN @MinutosTrabajados - @MinutosJornada ELSE 0 END;

        DECLARE @FechaExtra DATE = CAST(@FinJornadaDT AS DATE);
        DECLARE @EsFerODom  BIT  = dbo.fn_EsFeriadoODomingo(@FechaExtra);

        DECLARE @HorasExtraNormales  INT = 0;
      
        DECLARE @HorasExtraDobles    INT = 0;

        IF @MinutosExtra > 0
        BEGIN

            IF @EsFerODom = 0
            BEGIN

                DECLARE @MinHastaMedNoche INT = DATEDIFF(MINUTE, @FinJornadaDT,
                    CAST(CAST(DATEADD(DAY,1,CAST(@FinJornadaDT AS DATE)) AS VARCHAR(10)) AS DATETIME));

                IF @MinutosExtra <= @MinHastaMedNoche
                    
                    SET @HorasExtraNormales = @MinutosExtra / 60;
                ELSE
                BEGIN
                    
                    DECLARE @EsSigDiaFerODom BIT = dbo.fn_EsFeriadoODomingo(DATEADD(DAY,1,@FechaExtra));
                    SET @HorasExtraNormales = @MinHastaMedNoche / 60;
                    DECLARE @MinExtraEnSigDia INT = @MinutosExtra - @MinHastaMedNoche;
                    IF @EsSigDiaFerODom = 1
                        SET @HorasExtraDobles  = @MinExtraEnSigDia / 60;
                    ELSE
                        SET @HorasExtraNormales = @HorasExtraNormales + (@MinExtraEnSigDia / 60);
                END;
            END
            ELSE
                
                SET @HorasExtraDobles = @MinutosExtra / 60;
        END;

        
        DECLARE @MontoOrdinario     DECIMAL(12,2) = @HorasOrdinarias    * @SalarioXHora;
        DECLARE @MontoExtraNormal   DECIMAL(12,2) = @HorasExtraNormales * @SalarioXHora * 1.5;
        DECLARE @MontoExtraDoble    DECIMAL(12,2) = @HorasExtraDobles   * @SalarioXHora * 2.0;

        
        IF @HorasOrdinarias > 0
            INSERT INTO dbo.MovimientoPlanilla (IdPlanillaSemXEmpleado, IdTipoMovimiento, IdMarcaAsistencia, Fecha, Cantidad, Monto)
            VALUES (@IdPlanillaSemXEmpleado, 1, @IdMarca, @FechaEntrada, @HorasOrdinarias, @MontoOrdinario);

        
        IF @HorasExtraNormales > 0
            INSERT INTO dbo.MovimientoPlanilla (IdPlanillaSemXEmpleado, IdTipoMovimiento, IdMarcaAsistencia, Fecha, Cantidad, Monto)
            VALUES (@IdPlanillaSemXEmpleado, 2, @IdMarca, @FechaEntrada, @HorasExtraNormales, @MontoExtraNormal);

        
        IF @HorasExtraDobles > 0
            INSERT INTO dbo.MovimientoPlanilla (IdPlanillaSemXEmpleado, IdTipoMovimiento, IdMarcaAsistencia, Fecha, Cantidad, Monto)
            VALUES (@IdPlanillaSemXEmpleado, 3, @IdMarca, @FechaEntrada, @HorasExtraDobles, @MontoExtraDoble);

       
        UPDATE dbo.PlanillaSemXEmpleado
        SET
            SalarioBruto       = SalarioBruto       + @MontoOrdinario + @MontoExtraNormal + @MontoExtraDoble,
            HorasOrdinarias    = HorasOrdinarias    + @HorasOrdinarias,
            HorasExtraNormales = HorasExtraNormales + @HorasExtraNormales,
            HorasExtraDobles   = HorasExtraDobles   + @HorasExtraDobles
        WHERE IdPlanillaSemXEmpleado = @IdPlanillaSemXEmpleado;

       
        DECLARE @params NVARCHAR(500) = '{"empleado_doc":"' + @ValorDocumento +
            '","entrada":"' + CONVERT(VARCHAR,@FechaHoraEntrada,120) +
            '","salida":"'  + CONVERT(VARCHAR,@FechaHoraSalida,120)  + '"}';
        EXEC sp_RegistrarEvento @IdUsuarioSistema, 22, @IPOrigen, @params;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        INSERT INTO dbo.DBErrors (NombreSP, Mensaje, Severidad, Estado, Linea)
        VALUES ('sp_ProcesarAsistencia', ERROR_MESSAGE(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_LINE());
        DECLARE @msg VARCHAR(500) = ERROR_MESSAGE();
        RAISERROR('Error en sp_ProcesarAsistencia: %s', 16, 1, @msg);
    END CATCH;
END;
GO

PRINT 'SPs de asistencia creados exitosamente.';
GO
