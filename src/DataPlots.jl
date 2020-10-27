VERSION < v"0.1.0" && __precompile__()

module DataPlots

export plot_BC
export plot_proton
export plot_pbar
export plot_primary
export plot_secondary
export plot_e
export plot_pbarp
export plot_he
export plot_he34
export plot_be109
export modulation
export +
export /
export zero_
export purety

using Plots
using Interpolations
using FITSUtils
using Printf
using FITSIO
using LsqFit
using DelimitedFiles

"""
    modulation(ene::Array{T,1} where {T<:Real}, flux::Array{T,1} where {T<:Real};
               A::Int = 1, Z::Int = 1, phi::Real = 0)

Doing solar modulation for specified spectrum; ene in unit [GeV]; flux is the nucleon flux

# Arguments
* `A`,`Z`:  the A and Z of the particle
* `phi`:    modulation potential [unit: GV]
"""
function modulation(ene::Array{T,1} where {T<:Real}, flux::Array{T,1} where {T<:Real}; A::Int = 1, Z::Int = 1,phi::Real = 0)
  phi_ = phi* abs(Z) / max(A,1)
  m0 = A == 0 ? 0.511e-3 : 0.9382

  logene = log.(ene)
  itpspec = interpolate((range(logene[1],stop=last(logene),length=length(logene)),), log.(flux), Gridded(Linear()))
  spec = extrapolate(itpspec, Line())

  (ene, map(e-> e * (e + 2 * m0) / ( (e + phi_) * (e + phi_ + 2 * m0)) * exp(spec(log(e + phi_))), ene)) 
end

"""
    cholis_modulation(particle::Particle;t0::Int , t1::Int )

Doing solar modulation for specified particle using time , rigidity and charge-dependent solar modulation from Ilias Cholis et al. arx:1511.01507; 

# Arguments
* `particle`:  a struct for one kind of particle, if multiple particles are combined ,make sure the main Isotope is added first (example: spec2['Carbon_12']+spec2['Carbon_13'],
not spec2['Carbon_13']+spec2['Carbon_12'])
* `t0`and`t1`:    when did this experiment start and end, YYYYMMDD
* `Z`:    only specified when modulating antiproton or electron(z=-1)
"""
function cholis_modulation(particle::Particle;t0::Int = 20110519, t1::Int = 20160526)
  path1="/home/dm/zhaomj/software/source/solar-modulation/example_input_files/"
  path2="ism_spectrum.txt"
  write_spec(path1*path2,particle.Ekin,particle.dNdE)
  name=(particle.Z==-1 ? (particle.A==1 ? "antiproton" : "electron" ) : 
        particle.Z==1 ? (particle.A==1 ? "proton" : (particle.A==-1 ? "deuteron" : "positron" )) :  
        particle.Z==2 ? (particle.A==3 ? "helium3" : "helium4" ) :
        particle.Z==3 ? (particle.A==6 ? "lithium6" : "lithium7" ) : 
	particle.Z==4 ? (particle.A==9 ? "beryllium9" : "beryllium10" ) : 
	particle.Z==5 ? (particle.A==10 ? "boron10" : "boron11" ) :
	particle.Z==6 ? (particle.A==12 ? "carbon12" : "carbon13" ) :
	particle.Z==7 ? (particle.A==14 ? "nitrogen14" : "nitrogen15" ) :
	particle.Z==8 ? (particle.A==16 ? "oxygen16" : (particle.A==17 ? "oxygen17" : "oxygen18" ) ) : "?")
  t0_mjd=string(YMDtoMJD(t0))
  t1_mjd=string(YMDtoMJD(t1))
  change="s/particle_name: '.*'/particle_name: '$name'/g"
  change2="s/observation_starttime: .*#/observation_starttime: $t0_mjd #/g"
  change3="s/observation_endtime: .*#/observation_endtime: $t1_mjd #/g"
  run(`sed -i $change /home/dm/zhaomj/software/source/solar-modulation/analysis_options.yaml`)
  run(`sed -i $change2 /home/dm/zhaomj/software/source/solar-modulation/analysis_options.yaml`)
  run(`sed -i $change3 /home/dm/zhaomj/software/source/solar-modulation/analysis_options.yaml`)
  run(`python3.6 /home/dm/zhaomj/software/source/solar-modulation/modulate_main.py`)
  readdlm("/home/dm/zhaomj/software/source/solar-modulation/outfile/modulatd_spectrum.txt", ' ', Float64; comments=true, comment_char='#')
end

function fast_modulation(particle::Particle)
  path1="/home/dm/zhaomj/software/source/solar-modulation/example_input_files/"
  path2="ism_spectrum.txt"
  write_spec(path1*path2,particle.Ekin,particle.dNdE)
  run(`python3.6 /home/dm/zhaomj/software/source/solar-modulation/modulate_main.py`)
  readdlm("/home/dm/zhaomj/software/source/solar-modulation/outfile/modulatd_spectrum.txt", ' ', Float64; comments=true, comment_char='#')
end

function YMDtoMJD(t::Int)
   Y=t÷1e4-1900
   M=t÷100%100
   D=t%100
   L=(M==1 || M==2) ? 1 : 0
   return MJD=14956+D+(Y-L)*365.25÷1+(M+1+L*12)*30.6001÷1
end

function write_spec(fname::String,ene::Array{T,1} where {T<:Real}, dNdE::Array{T,1} where {T<:Real})
    open(fname, "w") do io
       writedlm(io, [ene dNdE])
    end
end

"""
    modulation(particle::Particle, phi::Real)

Doing solar modulation for specified spectrum inside the Particle structure

# Arguments
* `phi`:    modulation potential [unit: GV]
"""
function modulation(particle::Particle, phi::Real)
  particle.Ekin, particle.dNdE = modulation(particle.Ekin, particle.dNdE; A=particle.A, Z=particle.Z, phi=phi)
  count_R(particle)
end

"""
    dict_modulation(spec::Dict{String,Particle}, phi::Real = 0)

Doing solar modulation for a spectra dict of many Particles produced by FITSUtils

# Arguments
* `phi`:    modulation potential [unit: GV]
* `phi0`:   modulation potential for pbar [unit: GV]
"""
function dict_modulation(spec::Dict{String,Particle}, phi::Real = 0; phi0::Real = 0)
  phi == 0 && return spec

  mod_spec = Dict{String,Particle}()
  for k in keys(spec)
    mod_spec[k] = (phi0!=0 && spec[k].Z==-1) ? modulation(copy(spec[k]), phi0) : modulation(copy(spec[k]), phi)
  end

  return mod_spec
end

function get_data(fname::String; index::Real = 0.0, norm::Real = 1.0)
  basedir = dirname(@__FILE__)
  @assert isfile("$basedir/$fname")

  result = Dict{String, Array{Float64,2}}()
  key = ""

  open("$basedir/$fname") do file
    while !eof(file)
      line = readline(file)
      if line[1] == '#'
        key = line[2:length(line)]
        result[key] = Array{Float64,2}(undef, 0, 3)
      else
        if (key != "")
          lvec = map(x->parse(Float64, x), split(line))
          lvec[2:3] = map(v->v*lvec[1]^-index * norm, lvec[2:3])
          result[key] = vcat(result[key], lvec')
        end
      end
    end
  end

  result
end

function plot_data(data::Array{T,2} where { T <: Real },label::String)
  plot(data[:,1], data[:,2]; yerror=data[:,3], linewidth=0, marker=:dot, label=label,gridalpha=0.5,gridstyle=:dash,thickness_scaling = 2)
end

function plot_data!(data::Array{T,2} where { T <: Real },label::String)
  plot!(data[:,1], data[:,2]; yerror=data[:,3], linewidth=0, marker=:dot, label=label,gridalpha=0.5,gridstyle=:dash,thickness_scaling = 2)
end

function plot_comparison(plot_func, spectra::Array{Dict{String,Particle},1}, label::Array{String,2};
                         phi::Real = 0,phi0::Real = 0,
                         data::Array{String,1} = [],
                         datafile::String = "", index::Real = 0, norm::Real = 1,
                         xscale::Symbol = :log10, yscale::Symbol = :none,
                         ylabel::String = "")
  label.*=",phi="*string(phi)
  whole_ekin = true
  whole_rigidity = false
  if length(data) != 0
    pdata = get_data(datafile; index=index, norm=norm)

    if !mapreduce(k->haskey(pdata, k), &, data)
      data_keys = keys(pdata)
      throw("The specified data not found, note that the available data in file $datafile are:\n$data_keys")
    end
    if pure==0
     for k in data
       plot_data!(pdata[k], k)
     end
    end
    whole_rigidity = mapreduce(k->occursin("rigidity", k), &, data)
    whole_ekin = mapreduce(k->!occursin("rigidity", k), &, data)
  end

  if !whole_rigidity && !whole_ekin
    throw("The specified data should be all in rigidity or all in Ekin")
  end
  plot!(xscale=xscale, xlabel=whole_ekin ? "Ekin[GeV]" : "R[GV]", yscale=yscale, ylabel=whole_ekin ? ylabel : replace(replace(ylabel,"Ge"=>"G"),"E"=>"R"))

  mod_spectra = map(spec->dict_modulation(spec,phi;phi0=phi0), spectra)
  for i in 1:length(mod_spectra)
    ptc = plot_func(mod_spectra[i])*norm
    ene, flux = whole_ekin ? (ptc.Ekin, ptc.dNdE) : (ptc.R, ptc.dNdR)
    if pure!=0
     plot!(ene, flux; alpha=0.25,color=color,label="")
    else 
    plot!(ene, flux; label = i<=length(label) ? label[1,i] : "")
    end
    
  end
  plot!()
end

function get_func(a::Particle)
  etpE = extrapolate(interpolate((log.(a.Ekin),), log.(a.dNdE), Gridded(Linear())), Line())
  etpR = extrapolate(interpolate((log.(a.R),), log.(a.dNdR), Gridded(Linear())), Line())

  (x->exp(etpE(log(x))), x->exp(etpR(log(x))))
end

function op_particle(a::Particle, b::Particle, op)
  c = copy(a)
  efunc, rfunc = get_func(b)

  c.dNdE = @. op(c.dNdE, efunc(c.Ekin))
  c.dNdR = @. op(c.dNdR, rfunc(c.R))
  c
end

Base.:+(a::Particle, b::Particle) = op_particle(a, b, +)
Base.:-(a::Particle, b::Particle) = op_particle(a, b, -)
Base.:*(a::Particle, b::Particle) = op_particle(a, b, *)
Base.:/(a::Particle, b::Particle) = op_particle(a, b, /)

function Base.:*(a::Particle, n::Real)
  a.dNdE .*= n
  a.dNdR .*= n
  a
end

function rescale(a::Particle, index::Real)
  a.dNdE = @. a.dNdE * a.Ekin^index
  a.dNdR = @. a.dNdR * a.R^index
  a
end

function rescale(spec::Dict{String,Particle}, norm::Real)
  nspec = deepcopy(spec)
  for a in collect(keys(spec))
  nspec[a].dNdE = @. nspec[a].dNdE * norm
  nspec[a].dNdR = @. nspec[a].dNdR * norm
  end
  nspec
end

function zero_(spec::Dict{String,Particle})
  rescale(spec,0)
end

"""
    plot_BC(spectra::Array{Dict{String,Particle},1}, label::Array{String,2};
            phi::Real = 0, data::Array{String,1})  

    Ploting the B/C ratio of given spectra in comparison with the data

# Arguments
* `phi`:     modulation potential [unit: GV]
* `data`:    The dataset to plot
"""
function plot_BC(spectra::Array{Dict{String,Particle},1}, label::Array{String,2} = Array{String,2}(undef, (0,0)); phi::Real = 0, data::Array{String,1}=["AMS02(2011/05-2016/05)"])
  plot_comparison(spec-> (spec["Boron_10"] + spec["Boron_11"]) / (spec["Carbon_12"] + spec["Carbon_13"]),
                  spectra, label; phi=phi, data=data, datafile="bcratio.dat", ylabel="B/C")
end

function plot_BeB(spectra::Array{Dict{String,Particle},1}, label::Array{String,2} = Array{String,2}(undef, (0,0)); phi::Real = 0, data::Array{String,1}=["AMS02rigidity(2011/05-2016/05)"])
  plot_comparison(spec-> ((spec["Beryllium_7"] + spec["Beryllium_9"] + spec["Beryllium_10"]) / (spec["Boron_10"] + spec["Boron_11"])),
                  spectra, label; phi=phi, data=data, datafile="bebratio.dat", ylabel="Be/B")
end
"""
    plot_proton(spectra::Array{Dict{String,Particle},1}, label::Array{String,2};
            phi::Real = 0, data::Array{String,1})  

    Ploting the proton flux of given spectra in comparison with the data

# Arguments
* `phi`:     modulation potential [unit: GV]
* `data`:    The dataset to plot
"""
function plot_proton(spectra::Array{Dict{String,Particle},1}, label::Array{String,2} = Array{String,2}(undef, (0,0)); phi::Real = 0, data::Array{String,1}=["AMS02rigidity(2011/05-2018/05)"])
  plot_comparison(spec -> rescale(spec["Hydrogen_1"]+spec["Hydrogen_2"]+spec["secondary_protons"] , 2.7) * 1e4,
                  spectra, label; phi=phi, data=data, datafile="proton.dat", index=0,yscale=:log10, ylabel="\$E^{2.7}dN/dE [GeV^{2.7}(m^{2}*sr*s*GeV)^{-1}]\$")
end

function plot_primary(spectra::Array{Dict{String,Particle},1}, label::Array{String,2} = Array{String,2}(undef, (0,0)); phi::Real = 0, data::Array{String,1}=["AMS2017heliumrigidity(2011/05/19-2016/05/26)"],k::Real = 1)
  data=(data==["he"] ? ["AMS2017heliumrigidity(2011/05/19-2016/05/26)"] : 
        data==["c"]  ? ["AMS2017carbonrigidity(2011/05/19-2016/05/26)"] :
        data==["o"]  ? ["AMS2017oxygenrigidity(2011/05/19-2016/05/26)"] :
        data==["n"]  ? ["AMS2018nitrogenrigidity(2011/05/19-2016/05/26)"] : 
		data==["ne"]  ? ["AMS2020neonrigidity(2011/05/19-2018/05/26)"] : 
		data==["mg"]  ? ["AMS2020magnesiumrigidity(2011/05/19-2018/05/26)"] : 
		data==["si"]  ? ["AMS2020siliconrigidity(2011/05/19-2018/05/26)"] : data)
  _func=(occursin("helium", data[1])  ? spec -> rescale(spec["Helium_3"] + spec["Helium_4"], 2.7) * 1e4 : 
         occursin("carbon", data[1])  ? spec -> rescale(spec["Carbon_12"] + spec["Carbon_13"], 2.7) * 1e4 :
         occursin("oxygen", data[1])  ? spec ->rescale(spec["Oxygen_16"] + spec["Oxygen_17"] + spec["Oxygen_18"], 2.7) * 1e4 :
         occursin("nitrogen", data[1]) ? spec ->rescale(spec["Nitrogen_14"] + spec["Nitrogen_15"], 2.7) * 1e4 :
		 occursin("neon", data[1]) ? spec ->rescale(spec["Neon_20"] + spec["Neon_21"] + spec["Neon_22"], 2.7) * 1e4 :
		 occursin("magnesium", data[1]) ? spec ->rescale(spec["Magnesium_24"] + spec["Magnesium_25"] + spec["Magnesium_26"], 2.7) * 1e4 :
		 occursin("silicon", data[1]) ? spec ->rescale(spec["Silicon_28"] + spec["Silicon_29"] + spec["Silicon_30"], 2.7) * 1e4 : spec -> rescale(spec["Helium_3"] + spec["Helium_4"], 2.7) * 1e4)
		 k != 1 && (label.*=",k="*string(k))
  plot_comparison(_func,spectra, label; phi=phi, data=data, datafile="primary.dat", index=-2.7,norm=k,yscale=:log10, ylabel="\$E^{2.7}dN/dE [GeV^{2.7}(m^{2}*sr*s*GeV)^{-1}]\$")
end

function plot_secondary(spectra::Array{Dict{String,Particle},1}, label::Array{String,2} = Array{String,2}(undef, (0,0)); phi::Real = 0, data::Array{String,1}=["AMS2017lithiumrigidity(2011/05/19-2016/05/26)"],k::Real = 1)
  data=(data==["li"] ? ["AMS2017lithiumrigidity(2011/05/19-2016/05/26)"] : 
        data==["be"] ? ["AMS2017berylliumrigidity(2011/05/19-2016/05/26)"] :
        data==["b"]  ? ["AMS2017boronrigidity(2011/05/19-2016/05/26)"] : data)
  _func=(occursin("lithium", data[1])  ? spec ->rescale(spec["Lithium_6"] + spec["Lithium_7"], 2.7) * 1e4 : 
         occursin("beryllium", data[1]) ? spec -> rescale(spec["Beryllium_7"] + spec["Beryllium_9"] + spec["Beryllium_10"], 2.7) * 1e4 :
         occursin("boron", data[1])    ? spec -> rescale(spec["Boron_10"] + spec["Boron_11"], 2.7) * 1e4 : spec ->rescale(spec["Lithium_6"] + spec["Lithium_7"], 2.7) * 1e4 )
          k != 1 && (label.*=",k="*string(k))
  plot_comparison(_func,spectra, label; phi=phi, data=data, datafile="secondary.dat", index=-2.7,norm=k,yscale=:log10, ylabel="\$E^{2.7}dN/dE [GeV^{2.7}(m^{2}*sr*s*GeV)^{-1}]\$")
end

function plot_e(spectra::Array{Dict{String,Particle},1}, label::Array{String,2} = Array{String,2}(undef, (0,0)); phi::Real = 0, data::Array{String,1}=["AMS2019electron(2011/05/19-2017/11/12)"])
  data=(data==["e-"] ? ["AMS2019electron(2011/05/19-2017/11/12)"] : 
        data==["e+"]  ? ["AMS2019positron(2011/05/19-2017/11/12)"] :
        data==["eall"]  ? ["AMS02combined(2011/05-2018/05)"] :
        data==["fr"]  ? ["AMS2019fraction(2011/05/19-2017/11/12)"] :
        data==["pe"]  ? ["AMS02primaryele(computed)"] : data)
  _func=(occursin("electron", data[1])  ? spec -> rescale(spec["primary_electrons"] + spec["secondary_electrons"], 3.0) * 1e4 : 
         occursin("positron", data[1])  ? spec -> rescale(spec["secondary_positrons"] + spec["primary_positrons"], 3.0) * 1e4 :
        # occursin("computed", data[1])  ? spec -> rescale( deepcopy(spec["primary_electrons"]), 3.0) * 1e4 :
         occursin("computed", data[1])  ? spec -> rescale(spec["primary_electrons"] + spec["secondary_electrons"]-spec["secondary_positrons"], 3.0) * 1e4 :
         occursin("combined", data[1])  ? spec -> rescale(spec["primary_electrons"] + spec["secondary_electrons"]+spec["secondary_positrons"] + spec["primary_positrons"], 3.0) * 1e4 :
         occursin("fraction", data[1]) ? (spec->(spec["secondary_positrons"] + spec["primary_positrons"])/(spec["primary_electrons"] + spec["secondary_electrons"]+spec["secondary_positrons"] + spec["primary_positrons"])) : spec -> rescale(spec["primary_electrons"] + spec["secondary_electrons"], 3.0) * 1e4)
  index= occursin("fraction", data[1]) ? 0 : -3
  if occursin("fraction", data[1])
  yscale=:identity
  else yscale=:log10
  end
  plot_comparison(_func,spectra, label; phi=phi, data=data, datafile="e+e-.dat", index=index,yscale=yscale, ylabel=occursin("fraction", data[1]) ? "\$e^{+}/(e^{+}+e^{-})\$" : "\$E^{3}dN/dE [GeV^{3}(m^{2}*sr*s*GeV)^{-1}]\$")
end

function plot_he(spectra::Array{Dict{String,Particle},1}, label::Array{String,2} = Array{String,2}(undef, (0,0)); phi::Real = 0, data::Array{String,1}=["AMS2019he4(2011/05-2017/11)"])
  data=(data==["he4"] ? ["AMS2019he4(2011/05-2017/11)"] : 
        data==["he3"]  ? ["AMS2019he3(2011/05-2017/11)"] :
        data==["he3r"]  ? ["AMS2019he3rigidity(2011/05-2017/11)"] :
        data==["he4r"]  ? ["AMS2019he4rigidity(2011/05-2017/11)"] : data)
_func=(occursin("he4", data[1])  ? spec -> rescale(spec["Helium_4"] , 2.7) * 1e4 : 
       occursin("he3", data[1])  ? spec -> rescale(spec["Helium_3"] , 2.7) * 1e4 : spec -> rescale(spec["Helium_4"] , 2.7) * 1e4)
  plot_comparison(_func,spectra, label; phi=phi, data=data, datafile="heratio.dat", index=-2.7,yscale=:log10, ylabel="\$E^{2.7}dN/dE [GeV^{2.7}(m^{2}*sr*s*GeV)^{-1}]\$")
end

"""
    plot_pbar(spectra::Array{Dict{String,Particle},1}, label::Array{String,2};
            phi::Real = 0, data::Array{String,1})  

    Ploting the antiproton flux of given spectra in comparison with the data

# Arguments
* `phi`:     modulation potential [unit: GV]
* `data`:    The dataset to plot

# phi0: AMS02rigidity(2011/05-2015/05) may be 0.42 ,BESS-PolarII(2007/12-2008/01) may be 0.38,PAMELA(2006/07-2008/12) may be 0.41,PAMELA(2006/07-2009/12) may be 0.39,BESSI(2004/12) may be 0.39 
"""
function plot_pbar(spectra::Array{Dict{String,Particle},1}, label::Array{String,2} = Array{String,2}(undef, (0,0)); phi::Real = 0, data::Array{String,1}=["AMS02rigidity(2011/05-2018/05)"],k::Real = 1)           
  
  plot_comparison(spec -> rescale(spec["secondary_antiprotons"] + spec["tertiary_antiprotons"], 2.7) * 1e4*k,
                  spectra, label; phi=phi,phi0=phi, data=data, datafile="pbar.dat",index=-2.7, ylabel="\$E^{2.7}dN/dE [GeV^{2.7}(m^{2}*sr*s*GeV)^{-1}]\$")
 #plot_comparison(spec -> rescale(spec["DM_antiprotons"], 2.0) * 1e-3,
 #                spectra, label; phi=phi, data=data, datafile="pbar.dat",index=-2, yscale=:log, ylabel="\$E^{2}dN/dE [GeV^{2}(m^{2}*sr*s*GeV)^{-1}]\$")
end


function plot_pbarp(spectra::Array{Dict{String,Particle},1}, label::Array{String,2} = Array{String,2}(undef, (0,0)); phi::Real = 0,phi0::Real = 0, data::Array{String,1}=["AMS02rigidity(2011/05-2018/05)"]) 
  plot_comparison(spec -> (spec["secondary_antiprotons"] + spec["tertiary_antiprotons"]) / (spec["Hydrogen_1"] +spec["secondary_protons"]), 
                  spectra, label; phi=phi,phi0=phi0, data=data, datafile="pbarp.dat", ylabel="\$ ^{-}p/p \$")
end

function plot_be109(spectra::Array{Dict{String,Particle},1}, label::Array{String,2} = Array{String,2}(undef, (0,0)); phi::Real = 0, data::Array{String,1}=["ACE(1997/08/27-1999/04/09)","ISOMAX(1998/08/04-08/05)"])
  _func=spec -> (spec["Beryllium_10"] / spec["Beryllium_9"]) 
  plot_comparison(_func,spectra, label; phi=phi, data=data, datafile="beratio.dat", ylabel="\$^{10}Be/^{9}Be\$")
end

function plot_he34(spectra::Array{Dict{String,Particle},1}, label::Array{String,2} = Array{String,2}(undef, (0,0)); phi::Real = 0, data::Array{String,1}=["AMS2019rigidity(2011/05-2017/11)"])
  _func=spec -> (spec["Helium_3"] / spec["Helium_4"]) 
  plot_comparison(_func,spectra, label; phi=phi, data=data, datafile="heratio.dat", ylabel="\$^{3}He/^{4}He\$")
end

function plot_index(a::Particle)
  logene = log.(a.R)
  logflux = log.(a.dNdR)
  point=fitting([(logene[i],logflux[i]) for i=1:length(logene) if log(7.09)<logene[i]<log(12.0)])
  point=vcat(point,fitting([(logene[i],logflux[i]) for i=1:length(logene) if log(12.0)<logene[i]<log(16.6)]))
  point=vcat(point,fitting([(logene[i],logflux[i]) for i=1:length(logene) if log(16.6)<logene[i]<log(22.8)]))
  point=vcat(point,fitting([(logene[i],logflux[i]) for i=1:length(logene) if log(22.8)<logene[i]<log(41.9)]))
  point=vcat(point,fitting([(logene[i],logflux[i]) for i=1:length(logene) if log(41.9)<logene[i]<log(60.3)]))
  point=vcat(point,fitting([(logene[i],logflux[i]) for i=1:length(logene) if log(60.3)<logene[i]<log(192)]))
  point=vcat(point,fitting([(logene[i],logflux[i]) for i=1:length(logene) if log(192)<logene[i]<log(3300)]))
  plot!(exp.([pot[1] for pot in point]),[pot[2] for pot in point]; yerror=[pot[3] for pot in point], linewidth=0, marker=:dot,xscale=:log10)
end

function fitting(xydata::Array{Tuple{Float64,Float64},1})
  @. model(x, p) = p[1]*x+p[2]
  p0 = [-2.6, 1e1]
  fit=curve_fit(model, [xy[1] for xy in xydata], [xy[2] for xy in xydata], p0)  
  gamma=coef(fit)[1]
  err=stderror(fit)[1]
  min=minimum(abs.(fit.resid))
  for i=1:length(fit.resid)
    if min==abs.(fit.resid)[i]
      return ([xy[1] for xy in xydata][i],gamma,err)
    end
  end
end
function purety(A::Int = 0;col::Symbol = :yellow)
 global pure= A
 global color=col
end
purety(0)
end # module
