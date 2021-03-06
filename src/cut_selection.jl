function vA(v::Array{Float64,1}, A::Array{Float64,2})
    # Multiplies all rows of Matrix A by vector v
    r = similar(A)
    @inbounds for j = 1:size(A,2)
        @simd for i = 1:size(A,1)
            r[i,j] = v[j] * A[i,j]
        end
    end
    r
end


function get_idx(cuts::Array{Float64,2}, stage::Integer)
    cuts[:,1] .== repeat([stage], inner=size(cuts,1))
end


function get_cuts(cuts::Array{Float64,2}, stage::Integer)
    # Selects the alphas and betas of the cuts of the given stage
    cuts = cuts[get_idx(cuts, stage),:]
    dim_state = div(size(cuts,2)-3,2)
    cuts[:,3], cuts[:,4:(3+dim_state)]
end


function get_samplestates(cuts::Array{Float64,2}, stage::Integer)
    # Selects the sampled states of the cuts of the given stage
    cuts = cuts[get_idx(cuts, stage),:]
    dim_state = div(size(cuts,2)-3,2)
    cuts[:,(4+dim_state):end]
end


function L1_cut_selection(cuts::Tuple{Array{Float64,1},Array{Float64,2}}, sample_states::Array{Float64,2})
    (alphas, betas) = cuts
    nb_states = size(sample_states,1)
    ymax = zeros(nb_states)
    nondom_i = zeros(nb_states)

    # For each sampled state determine the non-dominated cut
    # Record the index and height of the non-dominated cut
    for s in 1:nb_states
        y,i = findmax(sum(vA(sample_states[s,:], betas),2) .+ alphas)
        ymax[s] = y
        nondom_i[s] = i
    end
    ymax, nondom_i
end


function load_L1_cuts!(md::SDDPModel, ymax_AA_M::Array{Float64,2}, nondom_i_AA_M::Array{Float64,2},
                         allcuts_fp::String, stage1cuts_fp::String, nb_iter::Integer, i::Integer)
    T_ = length(md.stages)-1 # Equals Number of stages (T) minus 1
    nb_nondom_cuts = zeros(T_)
    allcuts = readcsv(allcuts_fp)
    nb_cuts = size(allcuts,1)

    if i == 2
        # Initalize storage matrices
        # Max y value for [A]ll sampled states and [A]ll cuts
        ymax_AA_M = vcat(ymax_AA_M, zeros(div(nb_cuts,T_),T_))
        # Nondom cut idx for [A]ll sampled states and [A]ll cuts
        nondom_i_AA_M = vcat(nondom_i_AA_M, zeros(div(nb_cuts,T_),T_))
    elseif i >= 3
        currentcuts = allcuts[1:(nb_cuts-T_*nb_iter),:]
        newcuts = allcuts[(nb_cuts-T_*nb_iter+1):end,:]
        # Max y value for all [C]urrent sampled states and [C]urrent cuts
        ymax_CC_M = deepcopy(ymax_AA_M)
        # Nondom cut idx for all [C]urrent sampled states and [C]urrent cuts
        nondom_i_CC_M = deepcopy(nondom_i_AA_M)
        ymax_AA_M = zeros(div(nb_cuts,T_),T_)
        nondom_i_AA_M = zeros(div(nb_cuts,T_),T_)
    end

    for stage in 1:T_
        if i == 2
            # Determine ymax, non-dominated indices for all cuts
            ymax_AA, nondom_i_AA = L1_cut_selection(get_cuts(allcuts,stage),get_samplestates(allcuts, stage))
            ymax_AA_M[:,stage] = ymax_AA
            nondom_i_AA_M[:,stage] = nondom_i_AA
        elseif i >= 3
            # Update ymax, nondom_i for current states using new cuts
            ymax_AC, nondom_i_AC = ymax_CC_M[:,stage], nondom_i_CC_M[:,stage]
            ymax_NC, nondom_i_NC = L1_cut_selection(get_cuts(newcuts, stage),get_samplestates(currentcuts, stage))
            ii = ymax_NC .> ymax_CC_M[:,stage]
            ymax_AC[ii] = ymax_NC[ii] # max y value for all current sampled state (over all cuts)
            nondom_i_AC[ii] = nondom_i_NC[ii] + div(size(currentcuts,1),T_)
            ymax_AN, nondom_i_AN = L1_cut_selection(get_cuts(allcuts,stage),get_samplestates(newcuts,stage))
            ymax_AA_M[:,stage] = vcat(ymax_AC, ymax_AN)
            nondom_i_AA_M[:,stage] = vcat(nondom_i_AC, nondom_i_AN)
        end
        stage_cuts = allcuts[get_idx(allcuts,stage),:]
        # Record number of unique non-dominated cuts for the given stage
        nondom_idx = unique(Int.(nondom_i_AA_M[:,stage]))
        nb_nondom_cuts[stage] = size(nondom_idx,1)
        SDDP.loadcuts!(md, stage_cuts[nondom_idx,:])
    end
    md, ymax_AA_M, nondom_i_AA_M, nb_nondom_cuts
end
