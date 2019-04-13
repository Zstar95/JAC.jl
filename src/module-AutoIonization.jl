
"""
`module  JAC.AutoIonization`  
    ... a submodel of JAC that contains all methods for computing Auger properties between some initial and final-state 
        multiplets; it is using JAC, JAC.Radial.
"""
module AutoIonization

    using  Printf, JAC, JAC.ManyElectron, JAC.Radial
    global JAC_counter = 0

    
    """
    `struct  Settings`  ... defines a type for the details and parameters of computing Auger lines.

        + calcAnisotropy          ::Bool                         ... True, if the intrinsic alpha_2,4 angular parameters are to be calculated, 
                                                                     and false otherwise.
        + printBeforeComputation  ::Bool                         ... True, if all energies and lines are printed before their evaluation.
        + selectLines             ::Bool                         ... True, if lines are selected individually for the computations.
        + selectedLines           ::Array{Tuple{Int64,Int64},1}  ... List of lines, given by tupels (inital-level, final-level).
        + minAugerEnergy          ::Float64                      ... Minimum energy of free (Auger) electrons to be included.
        + maxAugerEnergy          ::Float64                      ... Maximum energy of free (Auger) electrons to be included.
        + maxKappa                ::Int64                        ... Maximum kappa value of partial waves to be included.
        + operator                ::String                       ... Auger operator that is to be used for evaluating the Auger amplitudes: 
                                                                     allowed values are: "Coulomb", "Breit", "Coulomb+Breit"
    """
    struct Settings
        calcAnisotropy            ::Bool         
        printBeforeComputation    ::Bool
        selectLines               ::Bool  
        selectedLines             ::Array{Tuple{Int64,Int64},1}
        minAugerEnergy            ::Float64
        maxAugerEnergy            ::Float64
        maxKappa                  ::Int64
        operator                  ::String 
    end 


    """
    `JAC.AutoIonization.Settings()`  ... constructor for the default values of AutoIonization line computations
    """
    function Settings()
        Settings(false, false, false, Array{Tuple{Int64,Int64},1}[], 0., 10e5, 100, "Coulomb")
    end


    # `Base.show(io::IO, settings::AutoIonization.Settings)`  ... prepares a proper printout of the variable settings::AutoIonization.Settings.
    function Base.show(io::IO, settings::AutoIonization.Settings) 
        println(io, "AutoIonization.Settings(with printBeforeComputation = $(settings.printBeforeComputation), selectLines = $(settings.selectLines), " *
                    "selectedLines = $(settings.selectedLines), ")
        println(io, "                 minAugerEnergy = $(settings.minAugerEnergy), maxAugerEnergy = $(settings.maxAugerEnergy), " *
                    "maxKappa = $(settings.maxKappa), calcAnisotropy = $(settings.calcAnisotropy), operator = $(settings.operator)) ")
    end


    """
    `struct  Channel`   ... defines a type for a AutoIonization channel to help characterize a scattering (continuum) state of many electron-states with 
                            a single free electron.

        + kappa          ::Int64                ... partial-wave of the free electron
        + symmetry       ::LevelSymmetry        ... total angular momentum and parity of the scattering state
        + phase          ::Float64              ... phase of the partial wave
        + amplitude      ::Complex{Float64}     ... Auger amplitude associated with the given channel.
    """
    struct  Channel
        kappa            ::Int64
        symmetry         ::LevelSymmetry
        phase            ::Float64
        amplitude        ::Complex{Float64}
    end


    """
    `struct  Line`  ... defines a type for a AutoIonization line that may include the definition of sublines and their corresponding amplitudes.

        + initialLevel   ::Level           ... initial-(state) level
        + finalLevel     ::Level           ... final-(state) level
        + electronEnergy ::Float64         ... Energy of the (incoming free) electron.
        + totalRate      ::Float64         ... Total rate of this line.
        + angularAlpha   ::Float64         ... Angular alpha_2 coefficient.
        + hasChannels    ::Bool            ... Determines whether the individual scattering (sub-) channels are defined in terms of their 
                                               free-electron energy, kappa and the total angular momentum/parity as well as the amplitude, or not.
        + channels       ::Array{AutoIonization.Channel,1}  ... List of AutoIonization channels of this line.
    """
    struct  Line
        initialLevel     ::Level
        finalLevel       ::Level
        electronEnergy   ::Float64
        totalRate        ::Float64
        angularAlpha     ::Float64
        hasChannels      ::Bool
        channels         ::Array{AutoIonization.Channel,1}
    end 


    """
    `JAC.AutoIonization.Line(initialLevel::Level, finalLevel::Level, totalRate::Float64)`  
        ... constructor for an AutoIonization line between a specified initial and final level.
    """
    function Line(initialLevel::Level, finalLevel::Level, totalRate::Float64)
        Line(initialLevel, finalLevel, 0., totalRate, 0., false, AutoIonization.Channel[])
    end


    # `Base.show(io::IO, line::AutoIonization.Line)`  ... prepares a proper printout of the variable line::AutoIonization.Line.
    function Base.show(io::IO, line::AutoIonization.Line) 
        println(io, "initialLevel:           $(line.initialLevel)  ")
        println(io, "finalLevel:             $(line.finalLevel)  ")
        println(io, "electronEnergy:         $(line.electronEnergy)  ")
        println(io, "totalRate:              $(line.totalRate)  ")
        println(io, "angularAlpha:           $(line.angularAlpha)  ")
        println(io, "hasChannels:            $(line.hasChannels)  ")
        println(io, "channels:               $(line.channels)  ")
    end


    """
    `JAC.AutoIonization.amplitude(kind::String, channel::AutoIonization.Channel, continuumLevel::Level, initialLevel::Level, grid::Radial.Grid; 
                         printout::Bool=true)`  
        ... to compute the kind = (Coulomb,  Breit  or Coulomb+Breit) Auger amplitude 
            <(alpha_f J_f, kappa) J_i || O^(Auger, kind) || alpha_i J_i>  due to the interelectronic interaction for the given 
            final and initial level. A value::ComplexF64 is returned.
    """
    function amplitude(kind::String, channel::AutoIonization.Channel, continuumLevel::Level, initialLevel::Level, grid::Radial.Grid; 
                       printout::Bool=true)
        nt = length(continuumLevel.basis.csfs);    ni = length(initialLevel.basis.csfs);    partial = Subshell(9,channel.kappa)
        if  printout  printstyled("Compute ($kind) Auger matrix of dimension $nt x $ni in the continuum- and initial-state bases " *
                                  "for the transition [$(initialLevel.index)- ...] and for partial wave $(string(partial)[2:end]) ... ", 
                                  color=:light_green)    end
        matrix = zeros(ComplexF64, nt, ni)
        #
        if      kind in [ "Coulomb", "Breit", "Coulomb*Breit"]        ## pure V^Coulomb interaction
        #-----------------------------------------------------
            for  r = 1:nt
                ##x if  continuumLevel.basis.csfs[r].J != finalLevel.J      ||  continuumLevel.basis.csfs[r].parity   != finalLevel.parity    continue    end 
                for  s = 1:ni
                    if  initialLevel.basis.csfs[s].J != initialLevel.J  ||  initialLevel.basis.csfs[s].parity != initialLevel.parity      continue    end 
                    wa = compute("angular coefficients: e-e, Ratip2013", continuumLevel.basis.csfs[r], initialLevel.basis.csfs[s])
                    me = 0.
                    for  coeff in wa[2]
                        if   kind in [ "Coulomb", "Coulomb+Breit"]    
                            me = me + coeff.V * JAC.InteractionStrength.XL_Coulomb(coeff.nu, 
                                                    continuumLevel.basis.orbitals[coeff.a], continuumLevel.basis.orbitals[coeff.b],
                                                    initialLevel.basis.orbitals[coeff.c],   initialLevel.basis.orbitals[coeff.d], grid)   end
                        if   kind in [ "Breit", "Coulomb*Breit"]    
                            me = me + coeff.V * JAC.InteractionStrength.XL_Breit(coeff.nu, 
                                                    continuumLevel.basis.orbitals[coeff.a], continuumLevel.basis.orbitals[coeff.b],
                                                    initialLevel.basis.orbitals[coeff.c],   initialLevel.basis.orbitals[coeff.d], grid)   end
                    end
                    matrix[r,s] = me
                end
            end 
            if  printout  printstyled("done. \n", color=:light_green)    end
            amplitude = transpose(continuumLevel.mc) * matrix * initialLevel.mc 
            amplitude = im^JAC.subshell_l(Subshell(101, channel.kappa)) * exp( -im*channel.phase ) * amplitude
            #
            #
         elseif  kind == "H-E"
        #--------------------
            iLevel = finalLevel;   fLevel = initialLevel
            amplitude = 0.;    error("stop a")
        else    error("stop b")
        end
        
        return( amplitude )
    end


    """
    `JAC.AutoIonization.channelAmplitude(kind::String, channel::AutoIonization.Channel, energy::Float64, finalLevel::Level, initialLevel::Level, grid::Radial.Grid)`  
        ... to compute the kind = (Coulomb,  Breit  or Coulomb+Breit) Auger amplitude  
            <(alpha_f J_f, kappa) J_i || O^(Auger, kind) || alpha_i J_i>  due to the interelectronic interaction for the given final and 
            initial level. A newChannel::AutoIonization.Channel is returned.
    """
    function channelAmplitude(kind::String, channel::AutoIonization.Channel, energy::Float64, finalLevel::Level, initialLevel::Level, grid::Radial.Grid)
        newiLevel = JAC.generateLevelWithSymmetryReducedBasis(initialLevel)
        newiLevel = JAC.generateLevelWithExtraSubshell(Subshell(101, channel.kappa), newiLevel)
        newfLevel = JAC.generateLevelWithSymmetryReducedBasis(finalLevel)
        cOrbital, phase  = JAC.Continuum.generateOrbital(energy, Subshell(101, channel.kappa), newfLevel, grid, contSettings)
        newcLevel  = JAC.generateLevelWithExtraElectron(cOrbital, channel.symmetry, newfLevel)
        newChannel = AutoIonization.Channel(channel.kappa, channel.symmetry, phase, 0.)
        amplitude = JAC.AutoIonization.amplitude(kind, channel, newcLevel, newiLevel, grid)

        newChannel = AutoIonization.Channel(newChannel.kappa, newChannel.symmetry, newChannel.phase, amplitude)    
        return( newChannel )
    end


    """
    `JAC.AutoIonization.computeAmplitudesProperties(line::AutoIonization.Line, nm::JAC.Nuclear.Model, grid::Radial.Grid, nrContinuum::Int64, 
                                           settings::AutoIonization.Settings; printout::Bool=true)` 
        ... to compute all amplitudes and properties of the given line; a line::Euer.Line is returned for which the amplitudes and properties 
            are now evaluated.
    """
    function computeAmplitudesProperties(line::AutoIonization.Line, nm::JAC.Nuclear.Model, grid::Radial.Grid, nrContinuum::Int64, 
                                         settings::AutoIonization.Settings; printout::Bool=true) 
        newChannels = AutoIonization.Channel[];   contSettings = JAC.Continuum.Settings(false, nrContinuum);   rate = 0.
        for channel in line.channels
            newiLevel = JAC.generateLevelWithSymmetryReducedBasis(line.initialLevel)
            newiLevel = JAC.generateLevelWithExtraSubshell(Subshell(101, channel.kappa), newiLevel)
            newfLevel = JAC.generateLevelWithSymmetryReducedBasis(line.finalLevel)
            cOrbital, phase  = JAC.Continuum.generateOrbitalForLevel(line.electronEnergy, Subshell(101, channel.kappa), newfLevel, nm, grid, contSettings)
            newcLevel  = JAC.generateLevelWithExtraElectron(cOrbital, channel.symmetry, newfLevel)
            newChannel = AutoIonization.Channel(channel.kappa, channel.symmetry, phase, 0.)
            amplitude = JAC.AutoIonization.amplitude(settings.operator, newChannel, newcLevel, newiLevel, grid, printout=printout)
            rate      = rate + conj(amplitude) * amplitude
            push!( newChannels, AutoIonization.Channel(newChannel.kappa, newChannel.symmetry, newChannel.phase, amplitude) )
        end
        totalRate = 2pi* rate;   angularAlpha = 0.
        newLine   = AutoIonization.Line(line.initialLevel, line.finalLevel, line.electronEnergy, totalRate, angularAlpha, true, newChannels)
        #
        if  settings.calcAnisotropy    angularAlpha = JAC.AutoIonization.computeIntrinsicAlpha(2, newLine)
            newLine   = AutoIonization.Line(line.initialLevel, line.finalLevel, line.electronEnergy, totalRate, angularAlpha, true, newChannels)
        end
        
        return( newLine )
    end


    """
    `JAC.AutoIonization.computeAmplitudesPropertiesPlasma(line::AutoIonization.Line, nm::JAC.Nuclear.Model, grid::Radial.Grid, nrContinuum::Int64, 
                                                 settings::PlasmaShift.AugerSettings; printout::Bool=true)`  
        ... to compute all amplitudes and properties of the given line but for the given plasma model; a line::AutoIonization.Line is returned 
            for which the amplitudes and properties are now evaluated.
    """
    function computeAmplitudesPropertiesPlasma(line::AutoIonization.Line, nm::JAC.Nuclear.Model, grid::Radial.Grid, nrContinuum::Int64, 
                                               settings::PlasmaShift.AugerSettings; printout::Bool=true) 
        newChannels = AutoIonization.Channel[];   contSettings = JAC.Continuum.Settings(false, nrContinuum);   rate = 0.
        for channel in line.channels
            newiLevel = JAC.generateLevelWithSymmetryReducedBasis(line.initialLevel)
            newiLevel = JAC.generateLevelWithExtraSubshell(Subshell(101, channel.kappa), newiLevel)
            newfLevel = JAC.generateLevelWithSymmetryReducedBasis(line.finalLevel)
            @warn "Adapt a proper continuum orbital for the plasma potential"
            cOrbital, phase  = JAC.Continuum.generateOrbitalForLevel(line.electronEnergy, Subshell(101, channel.kappa), newfLevel, nm, grid, contSettings)
            newcLevel  = JAC.generateLevelWithExtraElectron(cOrbital, channel.symmetry, newfLevel)
            newChannel = AutoIonization.Channel(channel.kappa, channel.symmetry, phase, 0.)
            @warn "Adapt a proper Auger amplitude for the plasma e-e interaction"
            amplitude = 1.0
            # amplitude  = JAC.AutoIonization.amplitude(settings.operator, newChannel, newcLevel, newiLevel, grid)
            rate       = rate + conj(amplitude) * amplitude
            push!( newChannels, AutoIonization.Channel(newChannel.kappa, newChannel.symmetry, newChannel.phase, amplitude) )
        end
        totalRate = 2pi* rate;   angularAlpha = 0.
        newLine   = AutoIonization.Line(line.initialLevel, line.finalLevel, line.electronEnergy, totalRate, angularAlpha, true, newChannels)
        
        return( newLine )
    end



    """
    `JAC.AutoIonization.computeIntrinsicAlpha(k::Int64, line::AutoIonization.Line)`  
        ... to compute the intrinsic alpha_k anisotropy parameter for the given line. A value::Float64 is returned.
    """
    function  computeIntrinsicAlpha(k::Int64, line::AutoIonization.Line)
        ##x println("line = $line")
        if  !line.hasChannels   error("No channels are defined for the given AutoIonization.line.")                   end
        wn = 0.;    for  channel in line.channels    wn = wn + conj(channel.amplitude) * channel.amplitude   end
        wa = 0.;    Ji = line.initialLevel.J;    Jf = line.finalLevel.J;
        for  cha  in line.channels  
            j = JAC.AngularMomentum.kappa_j(cha.kappa);    l = JAC.AngularMomentum.kappa_l(cha.kappa)
            ##x println("wn = $wn   j = $j   l =$l")
            for  chp  in line.channels  
                jp = JAC.AngularMomentum.kappa_j(chp.kappa);    lp = JAC.AngularMomentum.kappa_l(chp.kappa)
                ##x println("bracket = $(JAC.AngularMomentum.bracket([l, lp, j, jp])) ")
                ##x println("CG      = $(JAC.AngularMomentum.ClebschGordan(l, AngularM64(0), lp, AngularM64(0), AngularJ64(k), AngularM64(0))) ")
                ##x println("w-6     = $(JAC.AngularMomentum.Wigner_6j(Ji, j, Jf, jp, Ji, AngularJ64(k))) ")
                ##x println("w-6     = $(JAC.AngularMomentum.Wigner_6j(l,  j, AngularJ64(1//2), jp, lp, AngularJ64(k))) ")
                wa = wa + JAC.AngularMomentum.bracket([l, lp, j, jp]) *  
                          JAC.AngularMomentum.ClebschGordan(l, AngularM64(0), lp, AngularM64(0), AngularJ64(k), AngularM64(0)) *
                          JAC.AngularMomentum.Wigner_6j(Ji, j, Jf, jp, Ji, AngularJ64(k)) * 
                          JAC.AngularMomentum.Wigner_6j(l,  j, AngularJ64(1//2), jp, lp, AngularJ64(k)) * 
                          cha.amplitude * conj(chp.amplitude)
                ##x println("wa = $wa")
            end    
        end
        value = JAC.AngularMomentum.phaseFactor([Ji, +1, Jf, +1, AngularJ64(k), -1, AngularJ64(1//2)]) * 
                sqrt(JAC.AngularMomentum.twoJ(Ji) + 1) * wa / wn
        ##x println("value = $value")

        return( value )
    end



    """
    `JAC.AutoIonization.computeLines(finalMultiplet::Multiplet, initialMultiplet::Multiplet, nm::JAC.Nuclear.Model, grid::Radial.Grid, 
                            settings::AutoIonization.Settings; output=true, printout::Bool=true)`  
        ... to compute the Auger transition amplitudes and all properties as requested by the given settings. A list of 
            lines::Array{AutoIonization.Lines} is returned.
    """
    function  computeLines(finalMultiplet::Multiplet, initialMultiplet::Multiplet, nm::JAC.Nuclear.Model, grid::Radial.Grid, 
                           settings::AutoIonization.Settings; output=true, printout::Bool=true)
        println("")
        printstyled("JAC.AutoIonization.computeLines(): The computation of Auger rates and properties starts now ... \n", color=:light_green)
        printstyled("----------------------------------------------------------------------------------------------- \n", color=:light_green)
        println("")
        lines = JAC.AutoIonization.determineLines(finalMultiplet, initialMultiplet, settings)
        # Display all selected lines before the computations start
        if  settings.printBeforeComputation    JAC.AutoIonization.displayLines(lines)    end  
        # Determine maximum energy and check for consistency of the grid
        maxEnergy = 0.;   for  line in lines   maxEnergy = max(maxEnergy, line.electronEnergy)   end
        nrContinuum = JAC.Continuum.gridConsistency(maxEnergy, grid)
        # Calculate all amplitudes and requested properties
        newLines = AutoIonization.Line[]
        for  line in lines
            newLine = JAC.AutoIonization.computeAmplitudesProperties(line, nm, grid, nrContinuum, settings) 
            push!( newLines, newLine)
        end
        # Print all results to screen
        JAC.AutoIonization.displayRates(stdout, newLines, settings)
        JAC.AutoIonization.displayLifetimes(stdout, newLines)
        printSummary, iostream = JAC.give("summary flag/stream")
        if  printSummary   JAC.AutoIonization.displayRates(iostream, newLines, settings);   JAC.AutoIonization.displayLifetimes(iostream, newLines)     end
        #
        if    output    return( lines )
        else            return( nothing )
        end
    end



    """
    `JAC.AutoIonization.computeLinesCascade(finalMultiplet::Multiplet, initialMultiplet::Multiplet, nm::JAC.Nuclear.Model, grid::Radial.Grid, 
                            settings::AutoIonization.Settings; output=true, printout::Bool=true)`  
        ... to compute the Auger transition amplitudes and all properties as requested by the given settings. The computations
            and printout is adapted for large cascade computations by including only lines with at least one channel and by sending
            all printout to a summary file only. A list of lines::Array{AutoIonization.Lines} is returned.
    """
    function  computeLinesCascade(finalMultiplet::Multiplet, initialMultiplet::Multiplet, nm::JAC.Nuclear.Model, grid::Radial.Grid, 
                                  settings::AutoIonization.Settings; output=true, printout::Bool=true)
        
        lines = JAC.AutoIonization.determineLines(finalMultiplet, initialMultiplet, settings)
        # Display all selected lines before the computations start
        # if  settings.printBeforeComputation    JAC.AutoIonization.displayLines(lines)    end  
        # Determine maximum energy and check for consistency of the grid
        maxEnergy = 0.;   for  line in lines   maxEnergy = max(maxEnergy, line.electronEnergy)   end
        nrContinuum = JAC.Continuum.gridConsistency(maxEnergy, grid)
        # Calculate all amplitudes and requested properties
        newLines = AutoIonization.Line[]
        for  line in lines
            newLine = JAC.AutoIonization.computeAmplitudesProperties(line, nm, grid, nrContinuum, settings, printout=printout) 
            push!( newLines, newLine)
        end
        # Print all results to a summary file, if requested
        printSummary, iostream = JAC.give("summary flag/stream")
        if  printSummary   JAC.AutoIonization.displayRates(iostream, newLines, settings)     end
        #
        if    output    return( lines )
        else            return( nothing )
        end
    end



    """
    `JAC.AutoIonization.computeLinesPlasma(finalMultiplet::Multiplet, initialMultiplet::Multiplet, nm::JAC.Nuclear.Model, grid::Radial.Grid, 
                                  settings::PlasmaShift.AugerSettings; output=true)`  
        ... to compute the Auger transition amplitudes and all properties as requested by the given settings. A list of 
            lines::Array{AutoIonization.Lines} is returned.
    """
    function  computeLinesPlasma(finalMultiplet::Multiplet, initialMultiplet::Multiplet, nm::JAC.Nuclear.Model, grid::Radial.Grid, 
                                 settings::PlasmaShift.AugerSettings; output=true)
        println("")
        printstyled("JAC.AutoIonization.computeLinesPlasma(): The computation of Auger rates starts now ... \n", color=:light_green)
        printstyled("-------------------------------------------------------------------------------------- \n", color=:light_green)
        println("")
        augerSettings = JAC.AutoIonization.Settings(false, settings.printBeforeComputation, settings.selectLines, settings.selectedLines, 0., 1.0e6, 100, "Coulomb")
        lines = JAC.AutoIonization.determineLines(finalMultiplet, initialMultiplet, augerSettings)
        # Display all selected lines before the computations start
        if  settings.printBeforeComputation    JAC.AutoIonization.displayLines(lines)    end
        # Determine maximum energy and check for consistency of the grid
        maxEnergy = 0.;   for  line in lines   maxEnergy = max(maxEnergy, line.electronEnergy)   end
        nrContinuum = JAC.gridConsistency(maxEnergy, grid)
        # Calculate all amplitudes and requested properties
        newLines = AutoIonization.Line[]
        for  line in lines
            newLine = JAC.AutoIonization.computeAmplitudesPropertiesPlasma(line, nm, grid, nrContinuum, settings) 
            push!( newLines, newLine)
        end
        # Print all results to screen
        JAC.AutoIonization.displayRates(stdout, newLines, augerSettings)
        JAC.AutoIonization.displayLifetimes(stdout, newLines)
        printSummary, iostream = JAC.give("summary flag/stream")
        if  printSummary   JAC.AutoIonization.displayRates(iostream, newLines, augerSettings);   JAC.AutoIonization.displayLifetimes(iostream, newLines)     end
        #
        if    output    return( lines )
        else            return( nothing )
        end
    end


    """
    `JAC.AutoIonization.determineChannels(finalLevel::Level, initialLevel::Level, settings::AutoIonization.Settings)`  
        ... to determine a list of Auger Channel for a transitions from the initial to final level and by taking into account the particular 
            settings of for this computation; an Array{AutoIonization.Channel,1} is returned.
    """
    function determineChannels(finalLevel::Level, initialLevel::Level, settings::AutoIonization.Settings)
        channels  = AutoIonization.Channel[];   
        symi      = LevelSymmetry(initialLevel.J, initialLevel.parity);    symf = LevelSymmetry(finalLevel.J, finalLevel.parity) 
        kappaList = JAC.AngularMomentum.allowedKappaSymmetries(symi, symf)
        for  kappa in kappaList
            push!(channels, AutoIonization.Channel(kappa, symi, 0., Complex(0.)) )
        end
        return( channels )  
    end


    """
    `JAC.AutoIonization.determineLines(finalMultiplet::Multiplet, initialMultiplet::Multiplet, settings::AutoIonization.Settings)`  
        ... to determine a list of AutoIonization.Line's for transitions between levels from the initial- and final-state multiplets, and  
            by taking into account the particular selections and settings for this computation; an Array{AutoIonization.Line,1} is returned. 
            Apart from the level specification, all physical properties are set to zero during the initialization process.
    """
    function  determineLines(finalMultiplet::Multiplet, initialMultiplet::Multiplet, settings::AutoIonization.Settings)
        if    settings.selectLines    selectLines   = true
            selectedLines = JAC.determineSelectedLines(settings.selectedLines, initialMultiplet, finalMultiplet)
        else                          selectLines   = false
        end
    
        lines = AutoIonization.Line[]
        for  i = 1:length(initialMultiplet.levels)
            for  f = 1:length(finalMultiplet.levels)
                if  selectLines  &&  !((i,f) in selectedLines )    continue   end
                energy = initialMultiplet.levels[i].energy - finalMultiplet.levels[f].energy
                if   energy < settings.minAugerEnergy  ||  energy > settings.maxAugerEnergy    continue   end  

                channels = JAC.AutoIonization.determineChannels(finalMultiplet.levels[f], initialMultiplet.levels[i], settings) 
                push!( lines, AutoIonization.Line(initialMultiplet.levels[i], finalMultiplet.levels[f], energy, 0., 0., true, channels) )
            end
        end
        return( lines )
    end


    """
    `JAC.AutoIonization.displayLines(lines::Array{AutoIonization.Line,1})`  
        ... to display a list of lines and channels that have been selected due to the prior settings. A neat table of all selected 
            transitions and energies is printed but nothing is returned otherwise.
    """
    function  displayLines(lines::Array{AutoIonization.Line,1})
        println(" ")
        println("  Selected Auger lines:")
        println(" ")
        println("  ", JAC.TableStrings.hLine(150))
        sa = "  ";   sb = "  "
        sa = sa * JAC.TableStrings.center(18, "i-level-f"; na=2);                                sb = sb * JAC.TableStrings.hBlank(20)
        sa = sa * JAC.TableStrings.center(18, "i--J^P--f"; na=4);                                sb = sb * JAC.TableStrings.hBlank(22)
        sa = sa * JAC.TableStrings.center(14, "Energy"; na=4);              
        sb = sb * JAC.TableStrings.center(14, JAC.TableStrings.inUnits("energy"); na=4)
        sa = sa * JAC.TableStrings.center(14, "Energy e_A"; na=4);              
        sb = sb * JAC.TableStrings.center(14, JAC.TableStrings.inUnits("energy"); na=4)
        sa = sa * JAC.TableStrings.flushleft(37, "List of kappas and total symmetries"; na=4)  
        sb = sb * JAC.TableStrings.flushleft(37, "partial (total J^P)                "; na=4)
        println(sa);    println(sb);    println("  ", JAC.TableStrings.hLine(150)) 
        #   
        for  line in lines
            sa  = "  ";    isym = LevelSymmetry( line.initialLevel.J, line.initialLevel.parity)
                           fsym = LevelSymmetry( line.finalLevel.J,   line.finalLevel.parity)
            sa = sa * JAC.TableStrings.center(18, JAC.TableStrings.levels_if(line.initialLevel.index, line.finalLevel.index); na=2)
            sa = sa * JAC.TableStrings.center(18, JAC.TableStrings.symmetries_if(isym, fsym); na=4)
            sa = sa * @sprintf("%.8e", JAC.convert("energy: from atomic", line.initialLevel.energy))  * "    "
            sa = sa * @sprintf("%.8e", JAC.convert("energy: from atomic", line.electronEnergy))       * "   "
            kappaSymmetryList = Tuple{Int64,LevelSymmetry}[]
            for  i in 1:length(line.channels)
                push!( kappaSymmetryList, (line.channels[i].kappa, line.channels[i].symmetry) )
            end
            sa = sa * JAC.TableStrings.kappaSymmetryTupels(80, kappaSymmetryList)
            println( sa )
        end
        println("  ", JAC.TableStrings.hLine(150), "\n")
        #
        return( nothing )
    end


    """
    `JAC.AutoIonization.displayLifetimes(stream::IO, lines::Array{AutoIonization.Line,1})`  
        ... to list all lifetimes as associated with the selected lines. A neat table is printed but nothing is returned otherwise.
    """
    function  displayLifetimes(stream::IO, lines::Array{AutoIonization.Line,1})
        println(stream, " ")
        println(stream, "  Auger lifetimes, total rates and widths:")
        println(stream, " ")
        println(stream, "  ", JAC.TableStrings.hLine(115))
        sa = "  ";   sb = "  "
        sa = sa * JAC.TableStrings.center(10, "Level";    na=2);                           sb = sb * JAC.TableStrings.hBlank(12)
        sa = sa * JAC.TableStrings.center( 8, "J^P";      na=4);                           sb = sb * JAC.TableStrings.hBlank(12)
        sa = sa * JAC.TableStrings.center(14, "Lifetime"; na=4);               
        sb = sb * JAC.TableStrings.center(14,JAC.TableStrings.inUnits("time"); na=4)
        sa = sa * JAC.TableStrings.center(16, "Total rate"; na=6);               
        sb = sb * JAC.TableStrings.center(16,JAC.TableStrings.inUnits("rate"); na=4)
        sa = sa * JAC.TableStrings.center(48, "Widths"; na=2);       
        sb = sb * JAC.TableStrings.center(48, "Hartrees           Kaysers             eV"; na=2)
        println(stream, sa);    println(stream, sb);    println(stream, "  ", JAC.TableStrings.hLine(115)) 
        # 
        notYetDone = trues(1000)
        for  line in lines
            if  notYetDone[line.initialLevel.index]
                notYetDone[line.initialLevel.index] = false
                totalRate = 0.
                for  ln in lines
                    if  ln.initialLevel.index == line.initialLevel.index   totalRate = totalRate + ln.totalRate    end
                end
                sa  = "  ";    isym = LevelSymmetry( line.initialLevel.J, line.initialLevel.parity)
                sa = sa * JAC.TableStrings.center(10, JAC.TableStrings.level(line.initialLevel.index); na=2)
                sa = sa * JAC.TableStrings.center( 8, string(isym); na=4)
                sa = sa * @sprintf("%.8e", JAC.convert("time: from atomic",  1/totalRate))            * "     "
                sa = sa * @sprintf("%.8e", JAC.convert("rate: from atomic",    totalRate))            * "      "
                sa = sa * @sprintf("%.8e", totalRate)                                                 * "    "
                sa = sa * @sprintf("%.8e", JAC.convert("energy: from atomic to Kayser",  totalRate))  * "    "
                sa = sa * @sprintf("%.8e", JAC.convert("energy: from atomic to eV",      totalRate))  * "    "
                println(stream, sa)
            end
        end
        println(stream, "  ", JAC.TableStrings.hLine(115))
        #
        return( nothing )
    end


    """
    `JAC.AutoIonization.displayRates(stream::IO, lines::Array{AutoIonization.Line,1}, settings::AutoIonization.Settings)`  
        ... to list all results, energies, rates, etc. of the selected lines. A neat table is printed but nothing is returned 
            otherwise.
    """
    function  displayRates(stream::IO, lines::Array{AutoIonization.Line,1}, settings::AutoIonization.Settings)
        println(stream, " ")
        if  settings.calcAnisotropy    println(stream, "  Auger rates and intrinsic angular parameters: \n")
        else                           println(stream, "  Auger rates (without angular parameters): \n")        end
        println(stream, "  ", JAC.TableStrings.hLine(115))
        sa = "  ";   sb = "  "
        sa = sa * JAC.TableStrings.center(18, "i-level-f"; na=2);                         sb = sb * JAC.TableStrings.hBlank(20)
        sa = sa * JAC.TableStrings.center(18, "i--J^P--f"; na=4);                         sb = sb * JAC.TableStrings.hBlank(22)
        sa = sa * JAC.TableStrings.center(14, "Energy"   ; na=4);               
        sb = sb * JAC.TableStrings.center(14,JAC.TableStrings.inUnits("energy"); na=4)
        sa = sa * JAC.TableStrings.center(16, "Electron energy"   ; na=2);               
        sb = sb * JAC.TableStrings.center(16,JAC.TableStrings.inUnits("energy"); na=2)
        sa = sa * JAC.TableStrings.center(16, "Auger rate"; na=2);       
        sb = sb * JAC.TableStrings.center(16, JAC.TableStrings.inUnits("rate"); na=2)
        sa = sa * JAC.TableStrings.center(16, "alpha_2"; na=2);                           sb = sb * JAC.TableStrings.hBlank(18)     
        println(stream, sa);    println(stream, sb);    println(stream, "  ", JAC.TableStrings.hLine(115)) 
        #   
        for  line in lines
            sa  = "  ";    isym = LevelSymmetry( line.initialLevel.J, line.initialLevel.parity)
                           fsym = LevelSymmetry( line.finalLevel.J,   line.finalLevel.parity)
            sa = sa * JAC.TableStrings.center(18, JAC.TableStrings.levels_if(line.initialLevel.index, line.finalLevel.index); na=2)
            sa = sa * JAC.TableStrings.center(18, JAC.TableStrings.symmetries_if(isym, fsym); na=4)
            sa = sa * @sprintf("%.8e", JAC.convert("energy: from atomic", line.initialLevel.energy))  * "    "
            sa = sa * @sprintf("%.8e", JAC.convert("energy: from atomic", line.electronEnergy))       * "    "
            sa = sa * @sprintf("%.8e", JAC.convert("rate: from atomic", line.totalRate))              * "    "
            sa = sa * JAC.TableStrings.flushright(13, @sprintf("%.5e", line.angularAlpha))            * "    "
            println(stream, sa)
        end
        println(stream, "  ", JAC.TableStrings.hLine(115))
        #
        return( nothing )
    end

end # module