<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\AssignRoleRequest;
use App\Http\Requests\Api\V1\RemoveRoleRequest;
use App\Http\Resources\RoleResource;
use App\Http\Resources\UserResource;
use App\Models\Role;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class RoleController extends Controller
{
    public function index(): AnonymousResourceCollection
    {
        return RoleResource::collection(Role::all());
    }

    public function assign(AssignRoleRequest $request, User $user): JsonResponse
    {
        $roleIds = Role::whereIn('name', $request->roles)->pluck('id');

        $user->roles()->syncWithoutDetaching($roleIds);

        return response()->json([
            'message' => 'Roles assigned successfully.',
            'user' => new UserResource($user->load('roles')),
        ]);
    }

    public function remove(RemoveRoleRequest $request, User $user): JsonResponse
    {
        $roleIds = Role::whereIn('name', $request->roles)->pluck('id');

        $user->roles()->detach($roleIds);

        return response()->json([
            'message' => 'Roles removed successfully.',
            'user' => new UserResource($user->load('roles')),
        ]);
    }
}
