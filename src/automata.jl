
using AlgebraicDynamics
using Catlab
using Catlab.Doctrines
using RecursiveArrayTools

const FreeSMC = FreeSymmetricMonoidalCategory

struct System{T,F}
    inputs::Vector{Int}
    states::Vector{T}
    outputs::Vector{Int}
    f::F
end

# store states as lists of nested pairs

function rightObserve(f::FreeSMC.Hom{:generator}, curr)
    return f.args[1].outputs[curr]
end

function rightObserve(f::FreeSMC.Hom{:id}, curr)
    return curr
end

function rightObserve(composite::FreeSMC.Hom{:compose}, curr)
    g = composite.args[2]
    return rightObserve(g, curr[2])
end

function rightObserve(product::FreeSMC.Hom{:otimes}, curr)
    f,g = product.args[1], product.args[2]
    return(rightObserve(f, curr[1]), rightObserve(g, curr[2]))
end


function leftObserve(f::FreeSMC.Hom{:generator}, curr)
    return f.args[1].inputs[curr]
end

function leftObserve(f::FreeSMC.Hom{:id}, curr)
    return curr
end

function leftObserve(composite::FreeSMC.Hom{:compose}, curr)
    f = composite.args[1]
    return leftObserve(f, curr[1])
end

function leftObserve(product::FreeSMC.Hom{:otimes}, curr)
    f,g = product.args[1], product.args[2]
    return(leftObserve(f, curr[1]), leftObserve(g, curr[2]))
end

function initStates(f::FreeSMC.Hom{:generator})
    return f.args[1].states
end

function initStates(composite::FreeSMC.Hom{:compose})
    f,g = composite.args[1], composite.args[2]
    fstates = initStates(f)
    gstates = initStates(g)
    
    states = [(fs, gs) for fs=fstates, gs=gstates if rightObserve(f, fs)==leftObserve(g, gs)]
    return states
end

function initStates(product::FreeSMC.Hom{:otimes})
    f,g = product.args[1], product.args[2]
    fstates = initStates(f)
    gstates = initStates(g)
    
    states = [(fs, gs) for fs=fstates, gs=gstates if true] #the "if true" flattens the array
    return states
end

function next(sys::FreeSMC.Hom{:generator}, curr)
    f = sys.args[1]
    nexts = []
    for i=curr
        A = f.f[:, i] #grab the ith column
        append!(nexts, findall(x->x==1, A)) # append indices of rows showing a 1
    end
    return unique(nexts)
end

function next(sys::FreeSMC.Hom{:id}, curr)
    return curr
end

function next(composite::FreeSMC.Hom{:compose}, curr)
    nexts = []
    f, g = composite.args[1], composite.args[2]
    
    for (curr1, curr2)=curr
    
        fstates = next(f,curr1)
        gstates = next(g,curr2)
    
        append!(nexts,[(fs, gs) for fs=fstates, gs=gstates if rightObserve(f, fs)==leftObserve(g, gs)])
        end
    return nexts #don't unique because that would be very expensive
end
    


function next(product::FreeSMC.Hom{:otimes}, curr)
    nexts = []
    f, g = product.args[1], product.args[2]
    
    for (curr1, curr2)=curr
    
        fstates = next(f,curr1)
        gstates = next(g,curr2)
    
        append!(nexts,[(fs, gs) for fs=fstates, gs=gstates if true])
        end
    return nexts #don't unique because that would be very expensive
end
    

# Declare that real numbers are modeled as Int
R = Ob(FreeSMC, Int)

# Create decorating matrices for counters mod 3 and mod 2
counter3_matrix = reshape([0, 1, 0, 0, 0, 1, 1, 0, 0], 3,3)
counter2_matrix = reshape([0, 1, 1, 0], 2, 2)

counter3 = Hom(System([i%2 for i in 1:3], [1, 2], [i%2 for i in 1:3],  counter3_matrix), R, R)
counter2 = Hom(System([i%2 for i in 1:2], [1, 2], [i%2 for i in 1:2], counter2_matrix), R, R)

curr = initStates(counter3)
for i=1:4
    println(curr)
    curr = next(counter3, curr)
end
println(curr)

align = compose(counter2, counter3)
curr = initStates(align)
for i=1:4
    println(curr)
    curr = next(align, curr)
end
println(curr)

prod = otimes(counter2, counter3)
curr = initStates(prod)
for i=1:4
    println(curr)
    curr = next(prod, curr)
end
println(curr)